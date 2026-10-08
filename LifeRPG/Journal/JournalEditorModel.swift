import LifeRPGCore
import Observation
import SwiftData
import SwiftUI

/// The document the editor holds while it is open, and when it reaches the store.
///
/// A keystroke changes the text of the typed block in memory (`JournalDocument.settingText`) and
/// starts a 500 ms wait; the store is written when the wait ends, when the app leaves the
/// foreground, and at Close and Done. Every rule about what an edit does is a Core operation
/// (`JournalDocument+Editing`, `JournalEntries`, `JournalSaveState`); this class only holds the
/// result, the cursor, and the timer.
///
/// The row is made by `JournalEntries.save` once the document has a character in it, so opening an
/// empty day and closing it leaves no row, and a document emptied again deletes the row it made.
@MainActor
@Observable
final class JournalEditorModel {
    /// A request to put the cursor somewhere. `serial` makes two requests for the same place
    /// different, so a text view applies each one once.
    struct FocusRequest: Equatable {
        let serial: Int
        let focus: BlockFocus
    }

    /// What the page shows besides the blocks after a tap of "Ask me something". `serial` tells two
    /// equal toasts apart, so the second restarts its fade.
    struct Notice: Equatable {
        let serial: Int
        let value: JournalAskNotice
    }

    /// How long after the last change the store is written.
    static let debounce: Duration = .milliseconds(500)
    /// How long a toast stays; the safety line stays until it is dismissed.
    static let toastDuration: Duration = .seconds(4)

    let dayKey: String
    let language: JournalLanguage
    private(set) var document: JournalDocument
    private(set) var focusRequest: FocusRequest?
    /// A change is waiting for the debounce.
    private(set) var pendingSave = false
    private(set) var saveFailed = false
    private(set) var lastWriteAt: Date?
    /// Opened as done and not changed since: the header says "Reopened · saved".
    private(set) var reopenedDone: Bool
    /// A request from "Ask me something" is out. The pill shows a spinner and ignores taps.
    private(set) var asking = false
    private(set) var notice: Notice?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let now: () -> Date
    /// The caret: the block it is in and its `Character` offset there. Kept off the observed
    /// state, so moving it does not redraw the page.
    @ObservationIgnored private var cursor: BlockFocus?
    @ObservationIgnored private var waiting: Task<Void, Never>?
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var noticeSerial = 0
    @ObservationIgnored private var noticeTimer: Task<Void, Never>?
    /// Read when the pill is tapped, so a model that comes or goes, and the Settings switch, count
    /// from that moment.
    @ObservationIgnored private let wording: (JournalLanguage) -> (any JournalWording)?
    @ObservationIgnored private let includeWriting: () -> Bool

    init(dayKey: String, context: ModelContext, language: JournalLanguage = .system,
         now: @escaping () -> Date = Date.init,
         wording: @escaping (JournalLanguage) -> (any JournalWording)? = JournalAskWording.current,
         includeWriting: @escaping () -> Bool = { JournalAskSettings.includeWriting() }) {
        self.dayKey = dayKey
        self.language = language
        self.context = context
        self.now = now
        self.wording = wording
        self.includeWriting = includeWriting
        let entry = try? JournalEntries.entry(on: dayKey, in: context)
        let opened = JournalDocument(blocks: entry?.blocks ?? []).openedForEditing()
        document = opened.document
        reopenedDone = entry?.isDone ?? false
        cursor = opened.focus
        focusRequest = opened.focus.map { FocusRequest(serial: 1, focus: $0) }
        serial = 1
    }

    // MARK: what the header shows

    func saveLabel(at date: Date) -> String {
        JournalSaveState.label(pending: pendingSave, failed: saveFailed, lastWriteAt: lastWriteAt, now: date,
                               reopenedDone: reopenedDone)
    }

    var wordCountText: String { JournalPageText.words(document.wordCount) }

    func isUsed(_ key: JournalFixedKey) -> Bool { document.containsFixedKey(key) }

    /// Five model prompts are in: the pill is dimmed before the tap, by the rule `resolve` uses.
    var askIsCapped: Bool { JournalAsk.isCapped(document) }

    var cappedTooltip: String { JournalAsk.cappedTooltip(language: language) }

    // MARK: what the text views report

    func textChanged(_ blockID: UUID, to text: String) {
        guard let next = document.settingText(of: blockID, to: text), next != document else { return }
        document = next
        changed()
    }

    func cursorMoved(_ blockID: UUID, toCharacterOffset offset: Int) {
        cursor = BlockFocus(blockID: blockID, offset: offset)
    }

    /// A text view took the request, so a later redraw does not apply it again.
    func focusApplied(_ request: FocusRequest) {
        if focusRequest == request { focusRequest = nil }
    }

    // MARK: operations

    func insert(_ key: JournalFixedKey) {
        let seed = JournalPromptSeed.fixed(key, language: language)
        apply(document.insertingPrompt(seed, atBlock: cursor?.blockID, offset: cursor?.offset ?? 0))
    }

    /// Loads the on-device model while the page is open, so the first tap does not spend its
    /// timeout on that. A language the model is not used for (`JournalAsk.modelLanguages`) loads nothing.
    func prewarm() {
        guard JournalAsk.usesModel(for: language) else { return }
        wording(language)?.prewarm()
    }

    /// "Ask me something". The cursor is captured now; the request runs while the user keeps
    /// typing, and the result goes in at that cursor (`JournalAsk.insert`), so characters typed
    /// meanwhile stay where they were typed, after the new prompt when they were typed at the cursor.
    func ask() {
        guard !asking, !JournalAsk.isCapped(document) else { return }
        asking = true
        dismissNotice()
        let captured = cursor
        let snapshot = document
        let language = language
        let includeWriting = includeWriting()
        let signals = (try? JournalService.signals(on: dayKey, in: context))
            ?? JournalSignals(dayKey: dayKey, quests: [], occurrences: [], context: nil, ratings: [])
        let previous = JournalAsk.previousQuestions(before: dayKey, in: (try? JournalEntries.all(in: context)) ?? [])
        let model = wording(language)
        Task { [weak self] in
            let result = await JournalAsk.resolve(language: language, signals: signals, document: snapshot,
                                                  previousQuestions: previous, includeWriting: includeWriting,
                                                  wording: model, diagnose: { JournalAskDebug.record($0) })
            self?.finishAsk(result, at: captured)
        }
    }

    private func finishAsk(_ result: JournalAskResult, at captured: BlockFocus?) {
        asking = false
        let edit = JournalAsk.insert(result, into: document, atBlock: captured?.blockID,
                                     offset: captured?.offset ?? 0, language: language)
        apply(edit)
        if let value = JournalAsk.notice(for: result, inserted: edit != nil, document: document, language: language) {
            show(value)
        }
    }

    func dismissNotice() {
        noticeTimer?.cancel()
        notice = nil
    }

    private func show(_ value: JournalAskNotice) {
        noticeSerial += 1
        notice = Notice(serial: noticeSerial, value: value)
        noticeTimer?.cancel()
        guard case .toast = value else { return }
        let shown = noticeSerial
        noticeTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.toastDuration)
            guard !Task.isCancelled, self?.notice?.serial == shown else { return }
            self?.notice = nil
        }
    }

    /// Return at the end of a prompt's answer: free text starts below it.
    func returnAtEndOfAnswer(_ promptID: UUID) {
        apply(document.returningAtEndOfAnswer(promptID: promptID))
    }

    func backspaceAtStartOfEmptyAnswer(_ promptID: UUID) {
        apply(document.backspaceAtStartOfEmptyAnswer(promptID: promptID))
    }

    func removeQuestion(_ promptID: UUID) {
        apply(document.removingQuestion(promptID: promptID))
    }

    private func apply(_ edit: JournalEdit?) {
        guard let edit else { return }
        document = edit.document
        if let focus = edit.focus {
            serial += 1
            cursor = focus
            focusRequest = FocusRequest(serial: serial, focus: focus)
        }
        changed()
    }

    // MARK: saving

    private func changed() {
        reopenedDone = false
        pendingSave = true
        waiting?.cancel()
        waiting = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    /// Writes a change that is still waiting: as the app leaves the foreground, and at Close, which
    /// leaves the status as it was.
    func flush() {
        guard pendingSave else { return }
        write()
    }

    /// Done: the document is written, the entry is marked done, and the page may close. False when
    /// the store refused, so the page stays open with the words still on it.
    @discardableResult
    func done() -> Bool {
        write()
        guard !saveFailed else { return false }
        do {
            try JournalEntries.markDone(on: dayKey, in: context, now: now())
            try context.save()
            return true
        } catch {
            saveFailed = true
            return false
        }
    }

    private func write() {
        waiting?.cancel()
        waiting = nil
        do {
            try JournalEntries.save(document.blocks, on: dayKey, in: context, now: now())
            try context.save()
            saveFailed = false
            lastWriteAt = now()
        } catch {
            saveFailed = true
        }
        pendingSave = false
    }
}
