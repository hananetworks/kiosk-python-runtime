import collections
import os
import queue
import time
from pathlib import Path

import numpy as np
import openvino_genai as ov_genai
import psutil

try:
    import pyaudio
except ImportError:
    pyaudio = None


LANGUAGE_TOKEN_MAP = {"ko": "<|ko|>", "en": "<|en|>", "ja": "<|ja|>", "zh": "<|zh|>"}
RETRY_MESSAGES = {
    "ko": "다시 말씀해 주세요.",
    "en": "Please say it again.",
}


class KioskSTT:
    def __init__(
        self,
        local_model_path=None,
        device="CPU",
        rate=16000,
        chunk=1024,
        silence_threshold=0.012,
        preroll_chunks=25,
        end_silence_count=25,
        min_audio_sec=0.8,
        max_record_sec=15.0,
        save_log=True,
        base_dir=None,
    ):
        self.base_dir = Path(base_dir) if base_dir else Path(__file__).resolve().parent
        self.model_path = self._resolve_model_path(local_model_path)
        self.device = device
        self.rate = rate
        self.chunk = chunk
        self.silence_threshold = silence_threshold
        self.preroll_chunks = preroll_chunks
        self.end_silence_count = end_silence_count
        self.min_audio_sec = min_audio_sec
        self.max_record_sec = max_record_sec
        self.process = psutil.Process(os.getpid())
        start = time.time()
        self.pipe = ov_genai.WhisperPipeline(str(self.model_path), device=self.device)
        self.model_load_sec = round(time.time() - start, 3)

    def _resolve_model_path(self, local_model_path):
        model_path = Path(local_model_path) if local_model_path else self.base_dir / "models" / "whisper-small-int8-ov"
        required = [
            "openvino_encoder_model.xml",
            "openvino_encoder_model.bin",
            "openvino_decoder_model.xml",
            "openvino_decoder_model.bin",
            "openvino_tokenizer.xml",
            "openvino_tokenizer.bin",
            "openvino_detokenizer.xml",
            "openvino_detokenizer.bin",
        ]
        missing = [name for name in required if not (model_path / name).exists()]
        if missing:
            raise FileNotFoundError(f"OpenVINO model files are missing: {missing}")
        return model_path

    def normalize_language(self, language):
        aliases = {
            "kr": "ko",
            "kor": "ko",
            "korean": "ko",
            "eng": "en",
            "english": "en",
            "jp": "ja",
            "jpn": "ja",
            "japanese": "ja",
            "cn": "zh",
            "chn": "zh",
            "chinese": "zh",
        }
        normalized = aliases.get((language or "ko").lower().strip(), (language or "ko").lower().strip())
        return normalized if normalized in LANGUAGE_TOKEN_MAP else "ko"

    def record_audio(self):
        if pyaudio is None:
            raise RuntimeError("PyAudio is not installed for microphone capture.")
        audio_queue = queue.Queue()
        stream = None
        py_audio = None

        def callback(in_data, frame_count, time_info, status):
            audio_queue.put(in_data)
            return (None, pyaudio.paContinue)

        try:
            py_audio = pyaudio.PyAudio()
            stream = py_audio.open(
                format=pyaudio.paInt16,
                channels=1,
                rate=self.rate,
                input=True,
                frames_per_buffer=self.chunk,
                stream_callback=callback,
            )
            stream.start_stream()
            preroll = collections.deque(maxlen=self.preroll_chunks)
            chunks = []
            speaking = False
            silence = 0
            wait_start = time.time()

            while True:
                if time.time() - wait_start > self.max_record_sec:
                    if chunks:
                        break
                    raise TimeoutError("No speech detected before timeout.")

                data = np.frombuffer(audio_queue.get(), dtype=np.int16).astype(np.float32) / 32768.0
                if len(data) == 0:
                    continue

                rms = float(np.sqrt(np.mean(data**2)))
                if not speaking:
                    preroll.append(data)

                if rms >= self.silence_threshold or speaking:
                    if not speaking:
                        chunks.extend(list(preroll))
                        speaking = True
                    chunks.append(data)
                    silence = 0 if rms >= self.silence_threshold else silence + 1
                    if silence > self.end_silence_count:
                        break

            if not chunks:
                raise RuntimeError("No audio captured.")

            audio = np.concatenate(chunks).astype(np.float32)
            audio_sec = len(audio) / self.rate
            if audio_sec < self.min_audio_sec:
                raise RuntimeError(f"Audio is too short: {audio_sec:.2f}s")
            return audio, audio_sec
        finally:
            if stream is not None:
                stream.stop_stream()
                stream.close()
            if py_audio is not None:
                py_audio.terminate()

    def transcribe(self, audio, language):
        try:
            result = self.pipe.generate(audio, language=LANGUAGE_TOKEN_MAP.get(language, "<|ko|>"), task="transcribe")
        except TypeError:
            result = self.pipe.generate(audio)
        return str(result).strip()

    def transcribe_audio(self, audio, language="ko"):
        language = self.normalize_language(language)
        if not isinstance(audio, np.ndarray):
            audio = np.asarray(audio, dtype=np.float32)
        if audio.dtype != np.float32:
            audio = audio.astype(np.float32)
        if audio.ndim != 1:
            audio = audio.reshape(-1)
        peak = float(np.max(np.abs(audio))) if audio.size else 0.0
        if peak > 1.0:
            audio = audio / peak
        return self.transcribe(audio, language)

    def build_passthrough_result(self, raw_text):
        return {
            "matched": False,
            "action": "passthrough",
            "intent": None,
            "display_text": raw_text,
            "confidence": 0.0,
            "matched_by": "raw_text",
            "message": "",
        }

    def build_error_result(self, language):
        message_language = "en" if language == "en" else "ko"
        return {
            "matched": False,
            "action": "retry",
            "intent": None,
            "display_text": "",
            "confidence": 0.0,
            "matched_by": "error",
            "message": RETRY_MESSAGES[message_language],
        }

    def listen_once(self, screen, language="ko"):
        total_start = time.time()
        language = self.normalize_language(language)
        try:
            audio, audio_sec = self.record_audio()
            infer_start = time.time()
            raw_text = self.transcribe(audio, language)
            latency_sec = time.time() - infer_start
            cpu_percent = psutil.cpu_percent(interval=None)
            ram_mb = self.process.memory_info().rss / 1024 / 1024
            return {
                "success": True,
                "screen": screen,
                "language": language,
                "raw_text": raw_text,
                "corrected": self.build_passthrough_result(raw_text),
                "audio_sec": round(audio_sec, 3),
                "latency_sec": round(latency_sec, 3),
                "total_sec": round(time.time() - total_start, 3),
                "cpu_percent": round(cpu_percent, 1),
                "ram_mb": round(ram_mb, 1),
                "message": "recognition_completed",
            }
        except Exception as exc:
            return {
                "success": False,
                "screen": screen,
                "language": language,
                "raw_text": "",
                "corrected": self.build_error_result(language),
                "audio_sec": 0.0,
                "latency_sec": 0.0,
                "total_sec": round(time.time() - total_start, 3),
                "cpu_percent": 0.0,
                "ram_mb": 0.0,
                "message": str(exc),
            }
