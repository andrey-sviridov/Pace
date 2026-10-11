# Pace — решения и отложенные мелочи

Сгенерировано из журнала выполнения плана. Каждое решение — что решили, почему и чем грозит, если решение неверное.

## Решения

- | 1 ↔ controller | .gitignore | уже создан контроллером в 79c12d4 → Ruling ниже |
- | 4 ↔ 6 | AmountRule.afterEvent: SalaryEventKind, но тип объявлен в задаче 6 | КОНФЛИКТ → Ruling 2 |
- | 6 → 7 | findSalaryEvents(entries:) нужны записи, которые импорт только создаёт | КОНФЛИКТ порядка → Ruling 3 |
- | 7 ↔ 8 | Task 7 вызывает findMatchingEntry из Task 8 (позже) | КОНФЛИКТ порядка → Ruling 4 |
- | 2 test resource | Fixtures/*.pdf в .gitignore, ресурс SPM должен существовать | → Ruling 5 |
- Ruling 1: .gitignore уже есть (контроллер) — Task 1 только дополняет при необходимости — нет затрат.
- Ruling 2: `enum SalaryEventKind { advance, salary }` объявляется в Task 4 (Models/AmountRule.swift); Task 6 его использует — стоимость ошибки: переезд одного enum.
- Ruling 3: Task 7 импортирует в два прохода: (1) создать все записи (зарплата классифицируется напрямую по типу операции), (2) посчитать findSalaryEvents по всем записям счёта и применить правила сумм к переводам без категории — иначе правило «после аванса» не видит аванс из того же файла.
- Ruling 4: Task 7 пишет записи без склейки источников. Task 8 добавляет findMatchingEntry и подключает его в importStatement (строки выписки присоединяются к записям Apple Pay/SMS) — до Task 8 других источников нет, так что поведение не теряется.
- Ruling 5: в Fixtures кладётся `.gitkeep`, приёмочный тест `.disabled(if: файла нет)`.
- Ruling: CalendarDay fix via option (a) validate-at-construction (precondition in memberwise init, throwing Decodable, preconditionFailure instead of ??), not integer days-from-civil — user asked for simple readable code; cost if wrong: invalid date crashes instead of being normalized.
- Ruling: rename brief-mandated test `duplicateSourceKeyIsRejected` → `duplicateSourceKeyUpsertsIntoSingleRecord` — brief name asserts behaviour the DB doesn't have; cost if wrong: a test name.
- Ruling: purchase rows with income>0 && expense==0 (real Wildberries 11 ₸) → treated as refund (income) — cost if wrong: tiny amounts misfiled.
- Ruling: transfer entries use account = money source, counterAccount = destination; importer ensures deposit Account ("Депозит") and own Kaspi Account ("Kaspi *3436", kind .ownOtherCard) exist (create if missing, anchor 0) whenever it meets such a move — cost if wrong: Task 9 balance direction.
- Ruling: card account title from the most frequent masked card in rows' cardOrAccount ("Карта *2936"), fallback to account number — cost: cosmetic.
- Ruling: context.rollback() on import error accepted (also drops caller's unsaved changes; stores must save before import) — carry into Task 11 JournalStore.
- Ruling: deposit statement import adopts an existing deposit Account with empty number (fills the number) instead of creating a second one — cost if wrong: user with two deposits gets them merged until edited.
- Ruling: IncomingOperation gets `type: EntryType`; matcher adds `sameType` step — cost if wrong: an SMS whose type is mis-parsed won't attach (becomes separate entry, visible in review).
- Ruling: upgrade fee-overwrite-with-0 on attach to fix scope (money data loss) — write fee only when row fee > 0.
- Ruling: income entries with categoryId nil count as income (not as refund of uncategorized) — cost if wrong: an unknown refund inflates income slightly.
- Ruling: feeAmount of expense/transfer entries counts as spending in category "bankFees" (budget flexibleSpent + spendingByCategory + cumulative) — spec §5.3 "комиссия в аналитике идёт в Комиссии банка"; cost if wrong: ~200 ₸ per transfer.
- Ruling (carry Task 10): realtime (SMS/Apple Pay) income with amount ≥ 50% of the median salary → categoryId "salary" so the predicted salary isn't double-counted — cost if wrong: a big incoming transfer mislabeled salary (visible in review).
- Ruling (carry Task 10, core change): budget income excludes income entries whose account is .deposit (money stays on deposit, same reason as depositInterest) — cost if wrong: deposit-side income not spendable (correct by intent).
- Ruling: include amount left-boundary `(?<!\d)` fix (money: "Карта 1234 500 KZT" → 234500) and replace `Decimal(string:"0.5")!` force unwrap with a parameter — cheap money/crash fixes.
- Ruling (Tasks 13–17): screens read lists via SwiftData @Query (auto-refresh after save); writes go through stores with do/catch → errorStore.show. Store read methods are throws (accepted).
- Ruling (Task 12): onOpenURL while setup unfinished → feeds the setup flow; ImportError.unknownAccount → dialog create (card/deposit/other own card) or cancel, retry from kept Data; delete shared file from Documents/Inbox after read (error → errorStore); seeding inserts only missing categories/rules, never overwrites isBuiltIn == false.
- Ruling: account created from unknown-account dialog gets anchor = header.availableAmount on header.generatedOn, set AFTER the retried import — cost if wrong: user may need «Сверить остаток» once.
- Ruling: onboarding history must be a card statement — check header before writing, error «Для истории нужна выписка карты».
- Ruling: include cheap state fixes — hasFinishedSetup set only after successful save (revert on error); step 1 shows added count, not rows count.
- Ruling: include UX/correctness minors in the fix: hide zero legend rows + visible "Свободно" dot; BudgetBar overspend not double-counted in proportions (+ fix comment); single isAwaitingReview rule in core used by store and badge; updatePeriodMode rolls back on save failure.
- Ruling: include minors — merge candidates filtered by same type (+ sign in confirm); honest rename alert text; keep user's draft title on save error.
- Ruling: include — «Убрать лимит» reachable (bottom padding / hide tab bar on detail screens) + confirm; slider range starts at 1 000 (0 = no limit); card «в среднем»/«Как обычно» = median of the shown bars; ≥1 млн formatting; VoiceOver adjustable action saves.
- Ruling: switch to inline execution (executing-plans) from Task 17 on — user request (token cost); one final whole-branch review remains — cost: less per-task review.
- Task 18: Ruling: step 3 (running actions inside the Shortcuts app in the simulator) not performed — UI-driving Shortcuts is impractical here; verified instead: build clean, both intents in Metadata.appintents, core logic covered by RealtimeOperation/SourceMatcher/RemainingAfterPayment tests; real check moves to Task 19 on device — cost if wrong: an intent glue bug surfaces on device.
- User changes after Task 18 (commit above): Ruling: «Полмесяца» removed from UI; new AppSettings.hasAdvance (default true) — Home hero uses halfMonth when on + «за месяц» line from periodMode; stored .halfMonth migrates to salaryMonth+hasAdvance — user request — cost: none (halfMonth core kept).
- Ruling: employer field removed from UI (was unused; salary detected by «Поступление на счет ТОО» type); Kaspi cutoff moved to «Мои счета» → Kaspi account; new AccountsScreen (list/add/rename accounts, reconcile) — user request.
- Ruling: backup save/restore UI removed (core functions + tests kept) — user: «не нужна» — cost: no data export until re-added.
- Ruling: «Загрузить выписку PDF» in Settings via environment action importStatementFile = RootView.openSharedFile (same flow as share sheet).
- Ruling: reconcile moved to Home balance cards (sheet per account) and AccountsScreen; operation time shown in Review/Journal rows when entry.time exists, toggle shouldShowOperationTime (default true); hero font 32→28.
- Final: fixed deposit statement double-count — Ruling: refuse deposit statement import (ImportError.depositStatementNotSupported) until a real sample exists; deposit adoption removed — depositStatementIsRefusedAndWritesNothing RED→GREEN — cost: deposit only via «Сверить остаток» for now.
- Final: fixed Home limits counted in halfMonth — Home limits now from periodMode (monthly) like category card and Shortcut text — app wiring, verified by build (no core test: view wiring) — Ruling: no unit test for view wiring.

## Отложенные мелочи

- Task 1: minor (deferred): dotted date accepts "+13" / 2-digit year; `?? .gmt` dead fallback; no leap-day tests; no NBSP/tab test in normalizeDescription
- Task 2: minor (deferred): readRows silently drops non-date line without description cell / continuation before first row
- Task 2: minor (deferred): readability — findTextAfterLabel char-by-char matching + two overloads same name; makeRowWithContinuation copies 9 fields; StatementColumn.allCases order coupling implicit; date regex duplicated; header words overlap otherLabelPrefixes  (user priority: readability — final review should fix)
- Task 3: minor (deferred): no per-field key-sensitivity tests (amount/date/card/case; 10000 vs 10000.00); keyIsSha256Hex checks only length; makeTestRow helper lives in FingerprintTests (move to TestSupport.swift)
- Task 4: minor (deferred): JournalEntry.id not unique; createdAt default Date() in init; settingsHaveDefaults marked throws; no persistence test for AppSettings
- Task 4: minor (deferred): SpendingCategory.swift:7-8 new // comment splits /// doc from property
- Task 5: minor (deferred): ASHOP fragment (from A4SHOP) mis-hits VOLNASHOP → Дом; short fragments ERC/IZI/SPAR/CAFE latent over-match; one purchase 7 291 ₸ has empty merchant key (likely RBAPAY.KZ*TECHNODOM row — check parser for that row!); KASSA tail regex over-strips; no RED phase; test gaps (wrapped prefix, makeTitle Cyrillic)
- Task 6: minor (deferred): beforeDay rule stored as 0...0 sentinel (rules UI must special-case); median day truncation uncommented; makeClampedDay loop; one-off median includes itself; beforeDay boundary test asserts != rather than == nil
- Task 7: minor (deferred): acceptance test prints IMPORT-REPORT to stdout; var result + preconditionFailure around transaction; parallel arrays zip in addEntries; abs inconsistency; "Kaspi *3436" literal inside function; test gaps (overlapping repeated rows across files, rollback after insert, regular import with anchorDay nil, two Kaspi transfers → one account); zero-amount rows; negative fee if |expense|<|operation|
- Task 7: minor (deferred): two findAccount overloads (number:/kind:number:) easy to confuse
- Task 8: minor (deferred): mergeEntries no self-guard / no redirect of other refs / fee not merged; empty Депозит created when all deposit rows attach; importStatementInTransaction plan/attach block dense (findAttachTarget twice, parallel arrays, stale "Проход 1" comment); short-key contains over-match; boundary tests 10 min / 3 days
- Task 9: minor (deferred): formula lines ~160 chars (wrap); calculateAmountForPeriod name generic; BudgetSummary lacks expectedIncome for UI "факт + ожидается"; calculateObligatory many params; typical amount labels category flexible trick; balance relies only on affectsBalance (add day>=anchor) and === identity; Analytics today<start draws zeros; LimitStatus not Equatable; test gaps (early salary, late salary stretched, one-off vs expected, halfMonth no history, zero limit, fromDeposit balance); calendarMonth late-salary under-count
- Task 10: minor (deferred): recordRealtimeOperation 11 params (RealtimeInput struct?); loadAccountEntries loads all entries; save/rollback touch caller's unsaved changes; backup doesn't check duplicate unique keys; preconditionFailure path in SmsParser; repeated Shortcut run with different time → second entry (check on device); ≥50% median income → salary even from relatives (recategorize in review)
- Task 11: minor (deferred): theme computed twice in RootView; MainTabView in App/ (→ Screens/); no tests for formatTenge/makeErrorMessage; PDF parse on main thread (measure on device); B→A preferredColorScheme(nil) quirk; import-result line wrap «уже было»
- Task 12: minor (deferred): loadHistory/openSharedFile naming; SetupError lives in screen file; «Депозит» chosen for unrecognized statement may create 2nd deposit; RulesStore ternary; seeding/Inbox-path logic untested in repo (move to core + tests); MoneyField accepts "1,000"; second errorStore.show overwrites first
- Task 12: minor (deferred): dialog-created account stays without anchor if retried import fails (set anchor on first successful import when anchorDay nil); updateAnchor failure leaves unsaved fields + alert over sheet
- Task 13: minor (deferred): whole screen recomputed per body (~7 passes) — measure on device; wrong "один проход" comment; makePeriod could return end kind; segment id = title; deposit card shown as 0 when no deposit
- Task 13: minor (deferred): overspend overlay width uses full width not availableWidth; test name countsOnlyUnreviewedVisibleEntries misleading; MoneyTextStyle.hero unused
- Task 14: minor (deferred): «Всё ок» marks possible duplicates reviewed (show count of unresolved duplicates?); findWeekdayIndex naming; makeDayGroups array copy
- Task 14: minor (deferred): duplicate badge stuck if candidate's root is the entry itself; possibleDuplicateOf pointers to hidden entries not redirected on merge
- Task 15: minor (deferred): category not found → empty screen; slider rollback position 0; duplicate month-name arrays; salary thresholds 3rd copy (open question)
- Task 15: minor (deferred): confirmationDialog anchored on ScrollView (popover far from button); number+unit joined with regular space (₸/млн wrap) — use NBSP; VoiceOver decrement raises sub-1000 limit; Limits list edit sheet may still save flexible limit 0
- Task 16: minor (deferred): plan places obligatory step on last-payment day (Oct family step on 28th); plan uses planned obligatory, not max(plan,fact) like Home; no-limits flexible plan uses median; first salary period 2 months long; drag selection not visually checked
- Final: minor (deferred): «Всё ок» marks possible duplicates reviewed (keep SMS/Apple Pay off until handled); EntryDetail expense/fee of source hidden (sign); MoneyField no minus for overdraft; no user-created amount rules (spec §5.3); several cards: Home sums all cards but reconciles first, intent ignores `card`; importStatementInTransaction parallel arrays; SettingsStore duplicate update funcs; salary thresholds in 5 places (open question to user); device checks: repeated Shortcut run, PDF parse on main thread, Home recompute cost.
