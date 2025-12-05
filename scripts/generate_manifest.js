const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// GitHub Actions 워크플로우에서 생성되는 폴더명과 일치해야 함
const TARGET_DIR = path.join(__dirname, '../python-env');
const OUTPUT_FILE = 'manifest.json';

function getFileHash(filePath) {
    try {
        const buffer = fs.readFileSync(filePath);
        return crypto.createHash('sha256').update(buffer).digest('hex');
    } catch (err) { return null; }
}

function walkDir(dir, fileList = []) {
    if (!fs.existsSync(dir)) return fileList;
    const files = fs.readdirSync(dir);
    files.forEach(file => {
        const filePath = path.join(dir, file);
        if (fs.statSync(filePath).isDirectory()) {
            walkDir(filePath, fileList);
        } else {
            const relativePath = path.relative(TARGET_DIR, filePath).replace(/\\/g, '/');
            fileList.push({ path: relativePath, hash: getFileHash(filePath) });
        }
    });
    return fileList;
}

console.log(`🔍 Manifest 생성 시작... (Target: ${TARGET_DIR})`);

if (!fs.existsSync(TARGET_DIR)) {
    console.error(`❌ 오류: ${TARGET_DIR} 폴더가 없습니다. 빌드 스크립트 순서를 확인하세요.`);
    process.exit(1);
}

// [핵심] 버전 변경을 감지할 '중요 파일' 목록
const CRITICAL_FILES = [
    'kiosk_python.exe',
    'Lib/site-packages/torch/version.py',
    'Lib/site-packages/numpy/version.py',
    'requirements.txt'
];

const allFiles = walkDir(TARGET_DIR);
const criticalHashes = {};

CRITICAL_FILES.forEach(critPath => {
    const found = allFiles.find(f => f.path.endsWith(critPath));
    if (found && found.hash) criticalHashes[critPath] = found.hash;
});

const manifest = {
    generatedAt: new Date().toISOString(),
    criticalHashes: criticalHashes
};

fs.writeFileSync(OUTPUT_FILE, JSON.stringify(manifest, null, 2));
console.log(`✅ Manifest 생성 완료: ${OUTPUT_FILE}`);