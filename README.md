# MiniTG — минималистичный Telegram-клиент для iOS 12

Собирается на GitHub Actions (macOS-раннер, Mac не нужен).
Внутри: пре-собранный [TDLibFramework](https://github.com/Swiftgram/TDLibFramework) (TDLib 1.8.68, мин. iOS 12) + тонкий UIKit-клиент. Вход в приложении (телефон → код → 2FA).
api_id/api_hash уже вшиты в исходники (`app/Sources/Globals.swift`).

**Время сборки: ~5–10 минут** (кэш фреймворка между запусками).

## Как собрать

1. Создай репозиторий на GitHub (лучше **публичный** — macOS-раннеры бесплатны для public).
2. Запушь этот проект:

```bash
cd MiniTG
git init
git add .
git commit -m "MiniTG"
git branch -M main
git remote add origin https://github.com/ТВОЙ_НИК/mini-tg.git
git push -u origin main
```

3. Открой вкладку **Actions** в репо → workflow **Build MiniTG** → нажми **Run workflow**.
4. Сборка займёт 5–10 минут (первый запуск дольше — скачивается фреймворк). По окончании в **Actions → Build MiniTG → <run> → Artifacts** появится **MiniTG-ipa** — скачай и распакуй zip, внутри `MiniTG.ipa`.

## Как поставить на iPad

1. Скачай [Sideloadly](https://sideloadly.io) на ПК.
2. Подключи iPad кабелем.
3. Перетащи `MiniTG.ipa` в Sideloadly, введи свой Apple ID → **Start**.
4. На iPad: Настройки → Основные → Профили и управление устройством → доверяй своему Apple ID.
5. Открывай MiniTG, логинься телефоном/кодом/паролем.

## Структура

```
app/Sources/          Swift-код клиента (UIKit, iOS 12+)
app/TD-Bridge.h       C-объявления td_json API
tdlib/build-td-ios.sh сборка TDLib (arm64, статическая libtdjson)
build-app.sh          сборка .app → подпись → упаковка IPA
.github/workflows/build.yml
```

## Что умеет / чего нет

✅ Вход в приложении, авторизация сохраняется (база TDLib на устройстве)
✅ Список чатов (пиннед, непрочитанные, превью)
✅ Переписка: текст, фото (докачка), файлы (докачка), отправка текста и файлов
✅ Профиль, логаут
❌ Голосовые звонки, секретные чаты, сторис, каналы-админка — сознательно вырезано
