# Технический план переноса «Статей» в Telegram-iOS 11.15

## 1. Область работы и источники доказательств

База продукта — официальный исходный код Telegram-iOS 11.15, commit
`b1ebdab0dc3ae29dfda266f4bba0780bc842e73d`. Интерфейс, навигация, чат,
панель ввода и меню вложений должны оставаться реализацией 11.15. Источник
современного кода — официальный release-12.9.2, commit
`6ad963e5b62d354da79040f388ae2b9132fb17b8`: публичного исходного тега 12.9.3
в исследованном репозитории нет, поэтому совпадение с 12.9.3 подтверждается IPA,
а код сопоставляется с ближайшим официальным снимком 12.9.2.

Исследованные входные файлы:

| IPA | SHA-256 | Данные `Info.plist` |
|---|---|---|
| `/root/fuckgram/siftgram_11.15.ipa` | `4476a8db3bc4c5d38ad54fcff38b3f1638cb507c97e8f830ece8d592536b5d1f` | `11.15 (242)`, `app.swiftgram.ios`, executable `Swiftgram`, iOS 13.0 |
| `/root/fuckgram/telegram_12.9.3.ipa` | `f8c5f87571f1505579f4176c4c126f6a28e841ea20b877f80c1546025f18dfa4` | `12.9.3 (34622)`, `ph.telegra.Telegraph`, executable `Telegram`, iOS 13.0 |

Обе IPA были распакованы и исследованы как ZIP/Mach-O. `LC_ENCRYPTION_INFO_64`
показал `cryptid = 0` для обоих executable: у 11.15 `cryptoff = 81920`,
`cryptsize = 4096`; у 12.9.3 `cryptoff = 65536`, `cryptsize = 16384`.
Следовательно, исследованные Mach-O не зашифрованы. При этом Swift-символы
оптимизированной сборки не являются
эквивалентом исходному коду, поэтому выводы о реализации делаются только там,
где они подтверждены строками/метаданными IPA и официальным исходным снимком.

Наблюдаемые отличия IPA:

- Несжатые размеры binary по zip directory отличаются: `TelegramUIFramework`
  100 417 952 байт в 11.15 против 107 516 304 в 12.9.3;
  `TelegramCoreFramework` — 18 479 888 против 20 835 904; Postbox —
  4 085 984 против 3 901 968. Это доказывает, что binary не
  идентичны; их нельзя считать взаимозаменяемыми без проверки API
  и всего dependency graph.
- В 12.9.3 внутри `TelegramUIFramework.framework` есть
  `RichTextEditorUIKitResources.bundle`, а в 11.15 такого bundle нет.
- В raw bytes `TelegramUIFramework` 12.9.3 строки
  `RichTextAttachmentScreen` и `Chat/Attach Menu/Article` найдены по
  смещениям 72 319 440 и 75 021 248; в соответствующем binary
  11.15 обе строки отсутствуют.
- В обеих исследованных IPA присутствуют сторонние инжектированные dylib. В
  12.9.3 это, среди прочего, `Lead.dylib`, `zxPluginsInject.dylib` и несколько
  tweak-dylib; в 11.15 — `TGExtra.framework` и tweak-dylib. Они не являются
  доказательством архитектуры Telegram и исключены из переноса.
- `LC_LOAD_DYLIB` показывает у обоих основных app одинаковый штатный
  dependency spine: MtProtoKit, SwiftSignalKit, Postbox, TelegramCore и
  TelegramUI. `Lead`, `zxPluginsInject`, `TGExtra` и tweak-dylib загружаются
  только main executable соответствующего repackaged IPA, а не
  штатными Telegram framework.
- Размеры и состав `TelegramUIFramework`, `TelegramCoreFramework`, Postbox и
  SwiftSignalKit различаются. Эти framework нельзя механически копировать:
  они собраны против разных моделей данных и UI-графов.

Дополнительные проверяемые материалы находятся в
`docs/ARTICLES_BACKPORT.md`, `docs/richtext-composer.md` и
`docs/instantpage-richtext.md`.

## 2. Архитектура функции

Функция состоит не из одного экрана, а из сквозного пути:

1. **Точка входа в UI 11.15.** Пункт «Article» добавляется в существующее меню
   вложений 11.15 (`ChatControllerOpenAttachmentMenu.swift`). Он вызывает
   отдельный редактор через `ChatControllerArticles.swift`; обычная панель ввода
   11.15 не заменяется.
2. **Модель документа.** `RichTextEditorCore` хранит блоки и текстовые runs:
   абзацы/заголовки/списки, цитаты, code, таблицы, формулы и media. Модель не
   зависит от TelegramUI.
3. **Редактор UIKit.** `RichTextEditorUIKit` отображает документ и редактирует
   его; `RichTextAttachmentScreen` оборачивает редактор экраном, панелью действий,
   emoji/media/formula controls.
4. **Преобразование в сообщение.** `RichTextEditorMessageConversion` превращает
   документ в обычный `text + entities`, когда структура это допускает, либо в
   `InstantPage`, помещённую в `RichTextMessageAttribute`, для структурного
   содержимого. Файлы и изображения проходят через штатный media upload Core.
5. **Отправка/редактирование.** `EnqueueMessage`, `PendingMessageManager`,
   `PendingMessageUploadedContent`, `StandaloneSendMessage` и
   `RequestEditMessage` распознают `RichTextMessageAttribute`, загружают вложенные
   ресурсы и передают API `Api.InputRichMessage` через параметр `richMessage`
   методов send/edit.
6. **Получение и хранение.** `StoreMessage_Telegram.swift` разбирает API rich
   message; `SyncCore_RichTextMessageAttribute.swift` кодирует атрибут в Postbox;
   `AccountManager.swift` регистрирует его. `ApplyUpdateMessage.swift` обновляет
   ресурсы. `requestFullRichText` вызывает `messages.getRichMessage`, если сервер
   прислал сокращённое представление.
7. **Отображение.** `ChatMessageRichDataBubbleContentNode` встраивает renderer
   InstantPage V2 в обычный bubble/layout чата 11.15. `InstantPageUI` отвечает за
   раскладку текста, цитат, таблиц, collage/slideshow, изображений, видео и аудио.

Фактическая трасса подтверждается наличием `RichTextMessageAttribute` в
`PendingMessageUploadedContent.swift`, `StandaloneSendMessage.swift`,
`StoreMessage_Telegram.swift`, `ApplyUpdateMessage.swift` и вызовом
`Api.functions.messages.getRichMessage` в `TelegramEngineMessages.swift`.

## 3. Минимально необходимые компоненты и зависимости

### Протокол и Core

- `submodules/TelegramApi/Sources/Api0.swift` … `Api42.swift`: единый generated
  schema layer 228. Выборочные файлы старого layer 214 и нового layer 228
  смешивать нельзя: registry constructor id и generated enum должны оставаться
  согласованными.
- `submodules/TelegramCore/Sources/SyncCore/SyncCore_RichTextMessageAttribute.swift`.
- InstantPage/Media модели и codecs в `TelegramCore/Sources/SyncCore`,
  `ApiUtils/InstantPage.swift`, `ApiUtils/StoreMessage_Telegram.swift`.
- Rich-message upload/send/edit/draft pipeline в `PendingMessages`, `State` и
  `TelegramEngine/Messages`.
- `submodules/TelegramCore/Sources/ChatInputContent` и соответствующие conversion
  utilities `submodules/TextFormat/Sources/ChatInputContentConversion.swift`.
- Нужные typing-draft/Postbox views из современного Core; переносить их нужно
  вместе с readers/writers, а не менять формат одного конца.

### Редактор и представление

- `submodules/TelegramUI/Components/RichTextEditor` (`RichTextEditorCore` и
  `RichTextEditorUIKit`) и его `BUILD`/resource bundle.
- `submodules/TelegramUI/Components/RichTextAttachmentScreen`.
- `submodules/TelegramUI/Components/RichTextEditorMessageConversion`.
- `submodules/TelegramUI/Components/RichTextEditorMediaView`.
- `submodules/TelegramUI/Components/ArticlesFeature` — feature flag, по умолчанию
  включён; аварийное отключение через `UserDefaults["articles.enabled"]`.
- `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode`.
- InstantPage V2 additions в `submodules/InstantPageUI/Sources`.
- Из ComponentFlow 12.9 нужны только helper-методы `setBlur` и
  `animateBlur` в `submodules/ComponentFlow/Source/Base/Transition.swift`: их
  вызывают article action bar, InstantPage renderer и локальные glass controls.
  Весь современный ComponentFlow переносить не нужно.
- Ресурс `TelegramUI/Images.xcassets/Chat/Attach Menu/Article.imageset`.

### Точки интеграции 11.15

- `submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift` — только
  добавление пункта и вызова feature controller в старом меню.
- `submodules/TelegramUI/Sources/ChatControllerArticles.swift` — изолированный
  bridge create/edit/send.
- `submodules/TelegramUI/Sources/ChatController.swift` и BUILD-файлы — регистрация
  rich bubble/content node и вызовов без замены общего контроллера 12.9.
- `submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode` и
  `ChatRichTextEditorComposer` нужны как conversion bridge, но native rich editor
  не должен становиться production-панелью обычного сообщения.

Минимальность UI-интеграции проверена diff против baseline 11.15:
`ChatControllerOpenAttachmentMenu.swift` имеет 11 добавленных строк,
`ChatController.swift` — 5 добавленных и 1 удалённую. В старом
`submodules/AttachmentUI` добавлено только 14 строк
(`AttachmentController.swift`: 9, `AttachmentPanel.swift`: 5), без удалений
и без замены контроллера 11.15 на версию 12.9.

## 4. Существенные различия 11.15 и 12.9.3

| Уровень | 11.15 | Необходимое состояние backport |
|---|---|---|
| Telegram API | layer 214, нет полного rich-message контракта | целиком generated layer 228 |
| Message model | обычные text/entities/media | дополнительный `RichTextMessageAttribute` с InstantPage |
| Send/edit | не принимает rich payload | modern Core pipeline с legacy overload для UI 11.15 |
| Storage | нет регистрации rich attribute и новых drafts/views | совместимые readers/writers и регистрация типа |
| Editor | нет article editor/bundle | отдельные новые модули, открываемые из старого меню |
| Rendering | старый InstantPage и обычные bubble | V2 renderer только для rich bubble; окружающий chat UI остаётся 11.15 |
| Public Engine boundary | `Peer`, `Message`, `MediaResource`, старые сигнатуры | внутренний layer-228 Core плюс adapters, сохраняющие типы 11.15 |
| UI visual system | UI 11.15 | никаких global Liquid Glass/AttachmentUI 12.9; локальные 11.15-style adapters |

Разрыв Engine boundary подтверждён сравнением commit 11.15 с 12.9.2 и
реальными call sites старого UI: например, LocationUI преобразует `[Message]` в
`[EngineMessage]`, StorageUsageScreen хранит `[MessageId: Message]`, а avatar
экраны передают `MediaResource`. Поэтому обратные adapters должны находиться в
`TelegramCore/TelegramEngine`, а не требовать миграции всех экранов на UI 12.9.

## 5. Telegram API, schema и storage

1. Использовать один набор generated TelegramApi layer 228. Обязательные rich
   constructors/methods должны проверяться по `Api0…Api42`: registry
   `InputRichMessage` находится в `Api0.swift`, его generated-модель — в
   `Api13.swift`, `RichMessage` — в `Api24.swift`, а send/edit/get методы и
   параметр `richMessage` — в `Api42.swift`.
2. Зарегистрировать `RichTextMessageAttribute` в `AccountManager` и обеспечить
   Postbox encoding/decoding InstantPage и вложенных media.
3. Обновить StoreMessage parsing, pending outgoing message, standalone send,
   edit и update-resource logic. Обычные сообщения обязаны продолжать идти по
   прежнему пути с `richText: nil`.
4. Синхронизацию drafts переносить вместе с моделью `ChatInputContent` и
   typing-draft view. Проверять round-trip старых draft records и отсутствие
   обязательных новых полей при decode.
5. Миграция базы в виде разрушительного rewrite не требуется: новый message
   attribute добавочен. Все новые Codable/Postbox поля должны иметь default при
   чтении старых records. Это является требованием проверки; не следует считать
   совместимость доказанной только успешной компиляцией.

## 6. Порядок переноса и проверки

1. Зафиксировать baseline commit 11.15 и hashes IPA; не использовать сторонние
   Swiftgram/Lead изменения как source dependency.
2. Перенести единый TelegramApi layer 228 и добиться сборки API/Core без UI.
3. Перенести rich message model, InstantPage codecs, send/receive/edit/draft и
   Postbox views; добавить legacy overload/adapters для старых callers.
4. Перенести и протестировать `RichTextEditorCore` и conversions отдельно:
   document encode/decode, selection, entities и InstantPage round-trip.
5. Подключить UIKit editor, media view, attachment screen и только необходимые
   ресурсы.
6. Подключить V2 renderer и rich bubble к существующей message dispatch/layout
   системе 11.15.
7. Добавить пункт Article в старое attachment menu. Не заменять меню, input panel,
   navigation bar или visual effects глобально.
8. Собрать в GitHub Actions, устранить compile errors через boundary adapters,
   затем проверить один device IPA как ZIP и его `Payload/*.app/Info.plist`.
9. Runtime smoke tests: создать статью (text/heading/list/quote/table/media),
   отправить, перезапустить приложение, получить на втором аккаунте, открыть
   сокращённое сообщение через `getRichMessage`, отредактировать и переслать.
10. Regression tests UI 11.15: обычный send/edit, drafts, avatar upload, storage
    cleanup, live location, calls, stickers, invite/join и темы/цвета профиля.

## 7. GitHub-сборка и итоговый артефакт

Сборка выполняется только репозиторием GitHub, workflow
`.github/workflows/build.yml`, ветка `article-backport-11.15`, runner `macos-15`,
Xcode 16.4. Workflow использует официальные fake-codesigning материалы лишь для
анализа device target правилами Bazel; рабочая подпись для установки не создаётся.

Обязательные свойства результата:

- `Make.py` завершился с exit code 0 для `release_arm64`;
- существует `build/artifacts/Telegram.ipa`;
- workflow переименовывает/копирует его в единственный пользовательский файл
  `Telegram-11.15-articles-unsigned.ipa`;
- GitHub artifact содержит этот `.ipa` и `build-metadata.json`, но после
  скачивания пользователю передаётся один файл `.ipa`;
- `unzip -t` проходит, в архиве ровно один top-level `Payload/*.app`, версия
  остаётся 11.15, а SHA-256 вычисляется после скачивания;
- отсутствие production signature явно фиксируется: такой IPA не обязан
  устанавливаться на stock iOS без последующей подписи.

## 8. Риски и способы решения

- **Schema split-brain.** Частичный generated API приводит к неизвестным
  constructor ids. Решение: атомарный layer 228 и проверка registry.
- **Core/UI API drift.** Современный Core возвращает `EnginePeer/EngineMessage`
  и `EngineMediaResource`, старый UI ожидает raw Postbox-типы. Решение: узкие
  overload/adapters на boundary, подтверждённые call sites 11.15; не обновлять
  весь UI.
- **Старые Postbox records.** Новые обязательные поля могут сломать decode.
  Решение: optional/default decoding и тест запуска поверх копии базы 11.15.
- **Сокращённый rich payload.** Сервер может не прислать полную InstantPage.
  Решение: сохранять summary и догружать через `requestFullRichText`.
- **Media revalidation.** Media статьи лежат в attribute, а не в `message.media`.
  Решение: `FetchedMediaResource.swift` должен искать media внутри
  `RichTextMessageAttribute.instantPage`.
- **Циклы Bazel modules.** InstantPageUI уже транзитивно связан с chat input.
  Решение: передавать media view через factory/protocol; не добавлять обратную
  зависимость низкого уровня на TelegramUI.
- **iOS availability.** TextKit 2 и новые edit-menu API недоступны на iOS 13.
  Решение: TextKit 1 fallback и `@available` gates редактора.
- **Visual regression.** Импорт AttachmentUI/navigation/glass 12.9 изменит весь
  интерфейс. Решение: интегрировать только feature controller и старые primitives.
- **Неподписанный результат.** Fake profile нужен Bazel для device analysis, но
  не является пользовательской подписью. Решение: не удалять profile во время
  rules_apple build, после сборки честно маркировать IPA как unsigned.

## 9. Компоненты 12.9.3, которые переносить нельзя

- `TelegramUIFramework.framework` целиком и его `Assets.car`/локализации.
- Полный `AttachmentUI` 12.9.3 и новый глобальный attachment-menu controller.
- Liquid Glass/navigation/tab bar/global blur/effects 12.9.3, включая iOS 26
  visual stack. Допустимы только локальные adapters, визуально повторяющие 11.15.
- Новую production-панель обычного chat composer как обязательную замену панели
  11.15. Article editor остаётся отдельным attachment flow.
- Общие экраны settings/profile/chat list/calls/stories/gifts/ads из 12.9.3, если
  они не являются compile-time dependency rich message path.
- `Lead.dylib`, `zxPluginsInject.dylib`, `TGExtra.framework`, sideload fixers,
  screenshot/chat/notification tweaks и любые другие инжектированные компоненты
  исследованных IPA.
- Готовые binary frameworks Postbox/TelegramCore/TelegramUI из 12.9.3: проект
  должен собираться из согласованного source graph в GitHub.
- Bundle identifier, icons, entitlements и branding исследованной 12.9.3 IPA.

Любое расширение этого списка переносимых модулей допускается только при наличии
конкретной ошибки линковки/компиляции или трассы runtime rich-message path. Само
наличие компонента в IPA 12.9.3 не является доказательством его необходимости.
