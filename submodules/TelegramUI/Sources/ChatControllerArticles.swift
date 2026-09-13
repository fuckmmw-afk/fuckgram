import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import AttachmentUI
import LocationUI
import ArticlesFeature
import RichTextAttachmentScreen
import RichTextEditorCore
import RichTextEditorMessageConversion
import ChatRichTextEditorComposer
import TextFormat

extension ChatControllerImpl {
    private struct RichTextDraft: Codable {
        enum CodingKeys: String, CodingKey {
            case document
            case mediaKeys
            case mediaValues
            case emojiFilesKeys
            case emojiFilesValues
        }

        var document: RichTextEditorCoreDocument
        var media: [String: Media]
        var emojiFiles: [Int64: TelegramMediaFile]

        init(document: RichTextEditorCoreDocument, media: [String: Media], emojiFiles: [Int64: TelegramMediaFile]) {
            self.document = document
            self.media = media
            self.emojiFiles = emojiFiles
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.document = try container.decode(RichTextEditorCoreDocument.self, forKey: .document)
            let mediaKeys = try container.decode([String].self, forKey: .mediaKeys)
            let mediaValues = try container.decode([Data].self, forKey: .mediaValues)
            var media: [String: Media] = [:]
            for (key, value) in zip(mediaKeys, mediaValues) {
                if let object = PostboxDecoder(buffer: MemoryBuffer(data: value)).decodeRootObject() as? Media {
                    media[key] = object
                }
            }
            self.media = media
            let emojiFilesKeys = try container.decode([Int64].self, forKey: .emojiFilesKeys)
            let emojiFilesValues = try container.decode([Data].self, forKey: .emojiFilesValues)
            var emojiFiles: [Int64: TelegramMediaFile] = [:]
            for (key, value) in zip(emojiFilesKeys, emojiFilesValues) {
                if let object = PostboxDecoder(buffer: MemoryBuffer(data: value)).decodeRootObject() as? TelegramMediaFile {
                    emojiFiles[key] = object
                }
            }
            self.emojiFiles = emojiFiles
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.document, forKey: .document)
            var mediaKeys: [String] = []
            var mediaValues: [Data] = []
            for (key, value) in self.media {
                let encoder = PostboxEncoder()
                encoder.encodeRootObject(value)
                mediaKeys.append(key)
                mediaValues.append(encoder.makeData())
            }
            try container.encode(mediaKeys, forKey: .mediaKeys)
            try container.encode(mediaValues, forKey: .mediaValues)
            var emojiFilesKeys: [Int64] = []
            var emojiFilesValues: [Data] = []
            for (key, value) in self.emojiFiles {
                let encoder = PostboxEncoder()
                encoder.encodeRootObject(value)
                emojiFilesKeys.append(key)
                emojiFilesValues.append(encoder.makeData())
            }
            try container.encode(emojiFilesKeys, forKey: .emojiFilesKeys)
            try container.encode(emojiFilesValues, forKey: .emojiFilesValues)
        }
    }

    func presentRichTextComposer(completion: @escaping (AttachmentContainable?, AttachmentMediaPickerContext?) -> Void) {
        guard ArticlesFeature.isEnabled else {
            completion(nil, nil)
            return
        }

        var richTextDraftKey: EngineDataBuffer?
        if let peerId = self.chatLocation.peerId {
            let key = EngineDataBuffer(length: 8 + 8)
            key.setInt64(0, value: peerId.toInt64())
            key.setInt64(8, value: self.chatLocation.threadId ?? 0)
            richTextDraftKey = key
        }

        let controller = RichTextAttachmentScreen(
            context: self.context,
            mode: .standalone(savedDraft: nil, media: [:], emojiFiles: [:]),
            sendMessage: { [weak self] document, media, emojiFiles, sendWithoutFormatting in
                guard let self else {
                    return
                }
                if let richTextDraftKey {
                    let _ = self.context.engine.itemCache.remove(collectionId: Namespaces.CachedItemCollection.richTextComposerDrafts, id: richTextDraftKey).start()
                }

                let text: String
                let attributes: [MessageAttribute]
                if sendWithoutFormatting {
                    let content = chatInputContent(fromDocument: document, media: media, emojiFiles: emojiFiles)
                    let inputText = attributedString(from: content)
                    if inputText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return
                    }
                    let entities = generateTextEntities(inputText.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(inputText))
                    text = inputText.string
                    attributes = entities.isEmpty ? [] : [TextEntitiesMessageAttribute(entities: entities)]
                } else {
                    switch composeRichMessage(from: document, media: media, forSendPreview: true) {
                    case let .rich(instantPage):
                        text = ""
                        attributes = [RichTextMessageAttribute(instantPage: instantPage, fullInstantPage: nil)]
                    case let .plain(plainText, entities):
                        text = plainText
                        attributes = entities.isEmpty ? [] : [TextEntitiesMessageAttribute(entities: entities)]
                    case .empty:
                        return
                    }
                }
                let replyMessageSubject = self.presentationInterfaceState.interfaceState.replyMessageSubject
                let message: EnqueueMessage = .message(text: text, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: self.chatLocation.threadId, replyToMessageId: replyMessageSubject?.subjectModel, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                self.presentPaidMessageAlertIfNeeded(completion: { [weak self] postpone in
                    guard let self else {
                        return
                    }
                    self.chatDisplayNode.setupSendActionOnViewUpdate({
                        self.chatDisplayNode.collapseInput()
                        self.updateChatPresentationInterfaceState(animated: true, interactive: false, {
                            $0.updatedInterfaceState { $0.withUpdatedReplyMessageSubject(nil).withUpdatedSendMessageEffect(nil).withUpdatedPostSuggestionState(nil) }
                        })
                    }, nil)
                    self.sendMessages([message], postpone: postpone)
                })
            },
            syncContent: { [weak self] document, media, emojiFiles in
                guard let self, let richTextDraftKey else {
                    return
                }
                let draft = RichTextDraft(document: document, media: media, emojiFiles: emojiFiles)
                let _ = self.context.engine.itemCache.put(collectionId: Namespaces.CachedItemCollection.richTextComposerDrafts, id: richTextDraftKey, item: draft).start()
            },
            presentAttachmentMenu: { [weak self] photoVideoOnly, innerCompletion in
                self?.presentRichTextAttachmentMenu(photoVideoOnly: photoVideoOnly, completion: innerCompletion)
            },
            presentFormulaEditor: { [weak self] initialValue, innerCompletion in
                self?.presentFormulaEditor(initialValue: initialValue, completion: innerCompletion)
            }
        )
        completion(controller, controller.mediaPickerContext)
        self.controllerNavigationDisposable.set(nil)
    }

    func presentRichTextAttachmentMenu(photoVideoOnly: Bool, completion: @escaping (RichTextAttachmentScreen.RichTextAttachment) -> Void) {
        let presentationData = self.presentationData
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        items.append(ActionSheetButtonItem(title: presentationData.strings.Attachment_Location, color: .accent, action: { [weak self, weak actionSheet] in
            actionSheet?.dismissAnimated()
            guard let self else {
                return
            }
            let selfPeerId = self.context.account.peerId
            let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: selfPeerId))
            |> deliverOnMainQueue).startStandalone(next: { [weak self] selfPeer in
                guard let self, let selfPeer else {
                    return
                }
                let sharePeer = (self.presentationInterfaceState.renderedPeer?.peer).flatMap(EnginePeer.init)
                let controller = LocationPickerController(context: self.context, updatedPresentationData: self.updatedPresentationData, mode: .share(peer: sharePeer, selfPeer: selfPeer, hasLiveLocation: false), completion: { location, _, _, _, _ in
                    if let map = location as? TelegramMediaMap {
                        completion(.location(map))
                    }
                })
                self.push(controller)
            })
        }))
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        self.present(actionSheet, in: .window(.root))
        let _ = photoVideoOnly
    }

    func presentFormulaEditor(initialValue: String?, completion: @escaping (String) -> Void) {
        let controller = FormulaEditorScreen(context: self.context, initialValue: initialValue, completion: completion)
        self.present(controller, in: .window(.root))
    }
}
