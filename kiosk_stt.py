import collections, difflib, os, queue, re, time
from pathlib import Path

import numpy as np, openvino_genai as ov_genai, psutil
try:
    import pyaudio
except ImportError:
    pyaudio = None

AUTO_ACCEPT_THRESHOLD = 0.75
LANGUAGE_TOKEN_MAP = {"ko": "<|ko|>", "en": "<|en|>", "ja": "<|ja|>", "zh": "<|zh|>"}
SCREEN_CANDIDATES = {
    "ko": {
        "order_type": {"takeout": ["포장", "테이크아웃"], "store": ["매장", "먹고 갈게요"]},
        "menu": {
            "americano": ["아메리카노", "아아", "뜨아"], "cafe_latte": ["카페라떼", "라떼"], "cappuccino": ["카푸치노"],
            "espresso": ["에스프레소"], "vanilla_latte": ["바닐라라떼"], "caramel_macchiato": ["카라멜마끼아또", "카라멜마키아토"],
            "lemonade": ["레몬에이드", "레모네이드"], "grapefruit_ade": ["자몽에이드"], "peach_iced_tea": ["복숭아아이스티", "아이스티"],
            "green_tea": ["녹차"], "earl_grey": ["얼그레이"], "chamomile": ["캐모마일"],
        },
        "temperature": {"hot": ["핫", "뜨거운", "따뜻하게"], "iced": ["아이스", "차가운", "시원하게"]},
        "option": {"large": ["라지", "큰 사이즈"], "shot": ["샷 추가", "샷 하나 추가", "샷 두 개 추가"], "none": ["없어요", "괜찮아요", "기본"]},
        "payment": {"card": ["카드", "신용카드", "체크카드"], "samsung_pay": ["삼성페이"], "naver_pay": ["네이버페이"], "kakao_pay": ["카카오페이"]},
    },
    "en": {
        "order_type": {"takeout": ["take out", "to go", "takeaway"], "store": ["for here", "dine in", "eat here"]},
        "menu": {
            "americano": ["americano"], "cafe_latte": ["cafe latte", "latte"], "cappuccino": ["cappuccino"], "espresso": ["espresso"],
            "vanilla_latte": ["vanilla latte"], "caramel_macchiato": ["caramel macchiato"], "lemonade": ["lemonade"],
            "grapefruit_ade": ["grapefruit ade"], "peach_iced_tea": ["peach iced tea", "iced tea"], "green_tea": ["green tea"],
            "earl_grey": ["earl grey", "earl gray"], "chamomile": ["chamomile"],
        },
        "temperature": {"hot": ["hot"], "iced": ["iced", "ice", "cold"]},
        "option": {"large": ["large"], "shot": ["add shot", "extra shot"], "none": ["nothing", "no thanks", "basic"]},
        "payment": {"card": ["card", "credit card", "debit card"], "samsung_pay": ["samsung pay"], "naver_pay": ["naver pay"], "kakao_pay": ["kakao pay"]},
    },
}
DISPLAY_TEXT = {
    "ko": {"takeout": "포장", "store": "매장", "americano": "아메리카노", "cafe_latte": "카페라떼", "cappuccino": "카푸치노", "espresso": "에스프레소", "vanilla_latte": "바닐라라떼", "caramel_macchiato": "카라멜마끼아또", "lemonade": "레몬에이드", "grapefruit_ade": "자몽에이드", "peach_iced_tea": "복숭아아이스티", "green_tea": "녹차", "earl_grey": "얼그레이", "chamomile": "캐모마일", "hot": "HOT", "iced": "ICED", "large": "LARGE", "shot": "샷 추가", "none": "추가 옵션 없음", "card": "카드", "samsung_pay": "삼성페이", "naver_pay": "네이버페이", "kakao_pay": "카카오페이"},
    "en": {"takeout": "Take out", "store": "Dine in", "americano": "Americano", "cafe_latte": "Cafe Latte", "cappuccino": "Cappuccino", "espresso": "Espresso", "vanilla_latte": "Vanilla Latte", "caramel_macchiato": "Caramel Macchiato", "lemonade": "Lemonade", "grapefruit_ade": "Grapefruit Ade", "peach_iced_tea": "Peach Iced Tea", "green_tea": "Green Tea", "earl_grey": "Earl Grey", "chamomile": "Chamomile", "hot": "HOT", "iced": "ICED", "large": "LARGE", "shot": "Extra Shot", "none": "No Option", "card": "Card", "samsung_pay": "Samsung Pay", "naver_pay": "Naver Pay", "kakao_pay": "Kakao Pay"},
}
MESSAGES = {"ko": {"accept": "선택되었습니다.", "retry": "다시 말씀해 주세요."}, "en": {"accept": "Selected.", "retry": "Please say it again."}}


class KioskSTT:
    def __init__(self, local_model_path=None, device="CPU", rate=16000, chunk=1024, silence_threshold=0.012, preroll_chunks=25, end_silence_count=25, min_audio_sec=0.8, max_record_sec=15.0, save_log=True, base_dir=None):
        self.base_dir = Path(base_dir) if base_dir else Path(__file__).resolve().parent
        self.model_path = self._resolve_model_path(local_model_path)
        self.device, self.rate, self.chunk = device, rate, chunk
        self.silence_threshold, self.preroll_chunks, self.end_silence_count = silence_threshold, preroll_chunks, end_silence_count
        self.min_audio_sec, self.max_record_sec, self.process = min_audio_sec, max_record_sec, psutil.Process(os.getpid())
        start = time.time(); self.pipe = ov_genai.WhisperPipeline(str(self.model_path), device=self.device); self.model_load_sec = round(time.time() - start, 3)

    def _resolve_model_path(self, local_model_path):
        model_path = Path(local_model_path) if local_model_path else self.base_dir / "models" / "whisper-small-int8-ov"
        required = ["openvino_encoder_model.xml", "openvino_encoder_model.bin", "openvino_decoder_model.xml", "openvino_decoder_model.bin", "openvino_tokenizer.xml", "openvino_tokenizer.bin", "openvino_detokenizer.xml", "openvino_detokenizer.bin"]
        missing = [name for name in required if not (model_path / name).exists()]
        if missing:
            raise FileNotFoundError(f"OpenVINO model files are missing: {missing}")
        return model_path

    def normalize_language(self, language):
        aliases = {"kr": "ko", "kor": "ko", "korean": "ko", "eng": "en", "english": "en", "jp": "ja", "jpn": "ja", "japanese": "ja", "cn": "zh", "chn": "zh", "chinese": "zh"}
        return aliases.get((language or "ko").lower().strip(), (language or "ko").lower().strip())

    def normalize_text(self, text):
        text = re.sub(r"[\s.,?!]", "", (text or "").lower())
        for word in ["주세요", "부탁드려요", "부탁드립니다", "please", "iwant", "i'dlike"]:
            text = text.replace(word, "")
        return text

    def record_audio(self):
        if pyaudio is None:
            raise RuntimeError("PyAudio is not installed for microphone capture.")
        audio_queue = queue.Queue()
        stream = p = None
        def callback(in_data, frame_count, time_info, status): audio_queue.put(in_data); return (None, pyaudio.paContinue)
        try:
            p = pyaudio.PyAudio()
            stream = p.open(format=pyaudio.paInt16, channels=1, rate=self.rate, input=True, frames_per_buffer=self.chunk, stream_callback=callback)
            stream.start_stream(); preroll = collections.deque(maxlen=self.preroll_chunks); chunks = []; speaking = False; silence = 0; wait_start = time.time()
            while True:
                if time.time() - wait_start > self.max_record_sec:
                    if chunks: break
                    raise TimeoutError("No speech detected before timeout.")
                data = np.frombuffer(audio_queue.get(), dtype=np.int16).astype(np.float32) / 32768.0
                if len(data) == 0: continue
                rms = float(np.sqrt(np.mean(data ** 2)))
                if not speaking: preroll.append(data)
                if rms >= self.silence_threshold or speaking:
                    if not speaking: chunks.extend(list(preroll)); speaking = True
                    chunks.append(data); silence = 0 if rms >= self.silence_threshold else silence + 1
                    if silence > self.end_silence_count: break
            if not chunks: raise RuntimeError("No audio captured.")
            audio = np.concatenate(chunks).astype(np.float32); audio_sec = len(audio) / self.rate
            if audio_sec < self.min_audio_sec: raise RuntimeError(f"Audio is too short: {audio_sec:.2f}s")
            return audio, audio_sec
        finally:
            if stream is not None: stream.stop_stream(); stream.close()
            if p is not None: p.terminate()

    def transcribe(self, audio, language):
        try: result = self.pipe.generate(audio, language=LANGUAGE_TOKEN_MAP.get(language, "<|ko|>"), task="transcribe")
        except TypeError: result = self.pipe.generate(audio)
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

    def correct_by_screen(self, raw_text, screen, language):
        language = "en" if self.normalize_language(language) == "en" else "ko"
        candidates = SCREEN_CANDIDATES[language].get(screen)
        if not candidates:
            return {"matched": False, "action": "retry", "intent": None, "display_text": raw_text, "confidence": 0.0, "matched_by": "no_screen_candidates", "message": MESSAGES[language]["retry"]}
        norm_text, best_intent, best_score, best_method = self.normalize_text(raw_text), None, 0.0, "none"
        for intent, phrases in candidates.items():
            for phrase in phrases:
                norm_phrase = self.normalize_text(phrase)
                score, method = (1.0, "contains") if norm_phrase and norm_phrase in norm_text else (difflib.SequenceMatcher(None, norm_text, norm_phrase).ratio(), "fuzzy")
                if score > best_score: best_intent, best_score, best_method = intent, score, method
        if best_score >= AUTO_ACCEPT_THRESHOLD:
            return {"matched": True, "action": "accept", "intent": best_intent, "display_text": DISPLAY_TEXT[language].get(best_intent, best_intent), "confidence": round(best_score, 3), "matched_by": best_method, "message": MESSAGES[language]["accept"]}
        return {"matched": False, "action": "retry", "intent": None, "display_text": raw_text, "confidence": round(best_score, 3), "matched_by": "low_confidence", "message": MESSAGES[language]["retry"]}

    def listen_once(self, screen, language="ko"):
        total_start = time.time(); language = self.normalize_language(language)
        try:
            audio, audio_sec = self.record_audio()
            infer_start = time.time(); raw_text = self.transcribe(audio, language); latency_sec = time.time() - infer_start
            cpu_percent = psutil.cpu_percent(interval=None); ram_mb = self.process.memory_info().rss / 1024 / 1024
            return {"success": True, "screen": screen, "language": language, "raw_text": raw_text, "corrected": self.correct_by_screen(raw_text, screen, language), "audio_sec": round(audio_sec, 3), "latency_sec": round(latency_sec, 3), "total_sec": round(time.time() - total_start, 3), "cpu_percent": round(cpu_percent, 1), "ram_mb": round(ram_mb, 1), "message": "recognition_completed"}
        except Exception as exc:
            fallback_lang = "en" if language == "en" else "ko"
            return {"success": False, "screen": screen, "language": language, "raw_text": "", "corrected": {"matched": False, "action": "retry", "intent": None, "display_text": "", "confidence": 0.0, "matched_by": "error", "message": MESSAGES[fallback_lang]["retry"]}, "audio_sec": 0.0, "latency_sec": 0.0, "total_sec": round(time.time() - total_start, 3), "cpu_percent": 0.0, "ram_mb": 0.0, "message": str(exc)}
