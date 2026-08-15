# Cyber-Cafe-Management-DB (CCMDM)

Public corpus repo:
https://github.com/Cyber-Cafe-Management-DB/fantastic-db

Kafe disklerinden **FolderManifest** envanteri. Oyun dosyasi yok — klasor
listesi + PE surum bilgisi.

## Operator'a ne gidersin?

Sadece **bir dosya**: `CCMDM-Baslat.cmd` (token doldurulmus hali).

1. `CCMDM_GH_TOKEN=...` satirini doldur (owner/repo/branch zaten fantastic-db).
2. Cafeye at.
3. Sofor: **cift tikla**. UAC aciksa Evet. Sonra pencere yok; is arka planda biter.

Cmd ne yapar?

1. Admin + Hidden PowerShell acar (ExecutionPolicy Bypass).
2. GitHub raw'dan `CCMDM-Export.ps1` indirir (`%TEMP%`).
3. `C:\` **haric** tum disk harflerini tarar (maxDepth 5, oyun-root early-stop).
4. Rastgele klasor adi: `cafes/cafe-v9shd9/{tarih}/...`
5. Ayni repoya commit eder.
6. Log: `%TEMP%\ccmdm-*.log` (sorun olursa bak).

Calistigi klasorun onemi yok.

## Public repo icerigi

```text
CCMDM-Export.ps1     # cafelerin indirdigi tarayici (secret YOK)
cafes/               # gelen dump'lar
README.md
```

`CCMDM-Baslat.cmd` **public commit'e token'li haliyle konmaz** — sadece
senin private dagitiminda. Sablon: `tools/ccmdm-disk-corpus/CCMDM-Baslat.cmd`.

## Token: classic mi fine-grained mi?

Ikisi de olur. Tercih:

| Tur | Ne sec |
|-----|--------|
| **Fine-grained (onerilen)** | Resource: sadece `fantastic-db` · Contents: **Read and write** · Metadata: Read |
| **Classic** | Public repo icin yeterli scope: **`public_repo`**. (Tum private'lara da yetki istemiyorsan `repo` secme.) |

Classic daha genis yetki verir; bu is icin `public_repo` yeter. Fine-grained
daha dar ve guvenli. Cmd/token sizarsa hemen revoke et.

Default hedef:

- owner: `Cyber-Cafe-Management-DB`
- repo: `fantastic-db`
- branch: `main`

## Yerel debug (gelistirici)

```bat
set CCMDM_GH_OWNER=Cyber-Cafe-Management-DB
set CCMDM_GH_REPO=fantastic-db
set CCMDM_GH_TOKEN=...
powershell -NoProfile -ExecutionPolicy Bypass -File CCMDM-Export.ps1 -Silent:$false -LocalOnly
```
