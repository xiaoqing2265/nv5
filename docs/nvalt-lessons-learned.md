# nvALT 源码分析：检索、高亮、焦点的处理

## 核心发现

### 1. 高亮时机：在笔记加载后立即执行，同步完成

```objc
// AppController.m:1198-1248 displayContentsForNoteAtIndex:
- (BOOL)displayContentsForNoteAtIndex:(int)noteIndex {
    NoteObject *note = [notationController noteObjectAtFilteredIndex:noteIndex];
    if (note != currentNote) {
        [self _setCurrentNote:note];
        
        NSRange firstFoundTermRange = NSMakeRange(NSNotFound,0);
        NSRange noteSelectionRange = [currentNote lastSelectedRange];
        
        // 1. 设置内容
        [[textView textStorage] setAttributedString:[note contentString]];
        
        // 2. 立即高亮（同步）
        if ((unsigned)noteIndex != [notationController preferredSelectedNoteIndex])
            firstFoundTermRange = [textView highlightTermsTemporarilyReturningFirstRange:typedString 
                                   avoidHighlight:![prefsController highlightSearchTerms]];
        
        // 3. 如果没有保存的选区，使用第一个匹配位置
        if (!noteSelectionRange.length && firstFoundTermRange.location != NSNotFound)
            noteSelectionRange = firstFoundTermRange;
        
        // 4. 设置选区并滚动
        [textView setAutomaticallySelectedRange:noteSelectionRange];
        [textView scrollRangeToVisible:noteSelectionRange];
        
        return YES;
    }
    return NO;
}
```

**关键点**：
- ✅ 高亮在 `setAttributedString` **之后立即执行**，不是异步
- ✅ 高亮返回第一个匹配位置，用于自动选中
- ✅ 整个流程是**同步**的，没有 `DispatchQueue.main.async`
- ✅ 没有缓存机制（每次都重新高亮）

---

### 2. 高亮实现：使用临时属性，与 NV5 相同

```objc
// LinkingEditor.m:580-624 highlightTermsTemporarilyReturningFirstRange:
- (NSRange)highlightTermsTemporarilyReturningFirstRange:(NSString*)typedString avoidHighlight:(BOOL)noHighlight {
    CFStringRef quoteStr = CFSTR("\"");
    NSRange firstRange = NSMakeRange(NSNotFound,0);
    CFRange quoteRange = CFStringFind((CFStringRef)typedString, quoteStr, 0);
    
    // 分词：按空格或引号分割
    CFArrayRef terms = CFStringCreateArrayBySeparatingStrings(NULL, (CFStringRef)typedString, 
                                                              quoteRange.location == kCFNotFound ? CFSTR(" ") : quoteStr);
    if (terms) {
        CFStringRef bodyString = (CFStringRef)[self string];
        NSDictionary *highlightDict = [prefsController searchTermHighlightAttributes];
        
        for (termIndex = 0; termIndex < CFArrayGetCount(terms); termIndex++) {
            CFStringRef term = CFArrayGetValueAtIndex(terms, termIndex);
            if (CFStringGetLength(term) > 0) {
                // 查找所有匹配
                CFArrayRef ranges = CFStringCreateArrayWithFindResults(NULL, bodyString, term, 
                                                                       CFRangeMake(0, CFStringGetLength(bodyString)),
                                                                       kCFCompareCaseInsensitive);
                if (!ranges) continue;
                
                for (rangeIndex = 0; rangeIndex < CFArrayGetCount(ranges); rangeIndex++) {
                    CFRange *range = (CFRange *)CFArrayGetValueAtIndex(ranges, rangeIndex);
                    
                    if (range && range->length > 0) {
                        // 记录第一个匹配位置
                        if (firstRange.location > (NSUInteger)range->location) {
                            firstRange = *(NSRange*)range;
                            if (noHighlight) {
                                CFRelease(ranges);
                                goto returnEarly;
                            }
                        }
                        // 添加临时属性
                        [[self layoutManager] addTemporaryAttributes:highlightDict forCharacterRange:*(NSRange*)range];
                    }
                }
                CFRelease(ranges);
            }
        }
    returnEarly:
        CFRelease(terms);
    }
    return firstRange;
}
```

**关键点**：
- ✅ 使用 `layoutManager addTemporaryAttributes`（与 NV5 相同）
- ✅ 返回第一个匹配位置（用于自动选中）
- ✅ 支持 `avoidHighlight` 参数（只查找位置，不高亮）
- ✅ 使用 CoreFoundation API（性能优化）

---

### 3. 清除高亮：简单直接

```objc
// LinkingEditor.m:558-560
- (void)removeHighlightedTerms {
    [[self layoutManager] removeTemporaryAttribute:NSBackgroundColorAttributeName 
                                forCharacterRange:NSMakeRange(0, [[self string] length])];
}
```

**关键点**：
- ✅ 直接移除整个文档的 `NSBackgroundColorAttributeName`
- ✅ 没有缓存，没有状态检查

---

### 4. 搜索机制：C 字符串优化

```objc
// NotationController.m:1254-1306 filterNotesFromUTF8String:
- (BOOL)filterNotesFromUTF8String:(const char*)searchString forceUncached:(BOOL)forceUncached {
    BOOL stringHasExistingPrefix = YES;
    size_t oldLen = 0, newLen = 0;
    
    newLen = strlen(searchString);
    
    // PHASE 1: 判断是否可以增量搜索
    if (!currentFilterStr || forceUncached || ((oldLen = strlen(currentFilterStr)) > newLen) ||
        strncmp(currentFilterStr, searchString, oldLen)) {
        
        // 搜索词前缀不匹配，重新从所有笔记开始
        [notesListDataSource fillArrayFromArray:allNotes];
        stringHasExistingPrefix = NO;
        lastWordInFilterStr = 0;
        didFilterNotes = YES;
    }
    
    // PHASE 2: 实际搜索
    char *token, *separators = (strchr(searchString, '"') ? "\"" : " :\t\r\n");
    manglingString = replaceString(manglingString, searchString);
    
    while ((token = strsep(&preMangler, separators))) {
        if (*token != '\0') {
            filterContext.useCachedPositions = stringHasExistingPrefix && (token == manglingString + lastWordInFilterStr);
            filterContext.needle = token;
            
            if ([notesListDataSource filterArrayUsingFunction:(BOOL (*)(id, void*))noteContainsUTF8String 
                                                      context:&filterContext])
                didFilterNotes = YES;
        }
    }
    
    return didFilterNotes;
}
```

**关键点**：
- ✅ 使用 C 字符串（`const char*`）而不是 `NSString`（性能优化）
- ✅ 增量搜索：如果新搜索词是旧搜索词的前缀，只在当前结果中搜索
- ✅ 缓存位置：`useCachedPositions` 避免重复搜索同一个词

---

### 5. 焦点转移：没有特殊处理

nvALT 中**没有**显式的焦点转移代码在 `displayContentsForNoteAtIndex` 中。焦点转移由 `fieldAction` 处理：

```objc
// AppController.m:1300-1305
- (IBAction)fieldAction:(id)sender {
    [self createNoteIfNecessary];
    [window makeFirstResponder:textView];  // ← 直接、同步
}
```

**关键点**：
- ✅ 焦点转移和笔记加载是**分离**的
- ✅ `fieldAction` 只负责焦点，`displayContentsForNoteAtIndex` 只负责内容
- ✅ 没有复杂的时序协调

---

## NV5 vs nvALT 的关键差异

| 维度 | nvALT | NV5（修复前） | NV5（修复后） |
|---|---|---|---|
| **高亮时机** | `setAttributedString` 后立即同步执行 | `DispatchQueue.main.async` 异步执行 | 同步 + 异步（两次调用） |
| **高亮缓存** | 无缓存，每次都重新高亮 | `lastHighlightQuery` 缓存 | 缓存 + `loadNote` 时重置 |
| **焦点转移** | `fieldAction` 直接调用 `makeFirstResponder` | SwiftUI 焦点系统 + 多层异步 | `MainWindowController` 直接调用 |
| **高亮和焦点关系** | 完全独立，无耦合 | 在同一个 `updateNSView` 中，有时序依赖 | 仍在同一个 `updateNSView` 中 |
| **搜索优化** | C 字符串 + 增量搜索 + 缓存位置 | Swift String + 每次全量搜索 | 同左 |

---

## 对 NV5 的启示

### 问题 1：高亮被调用两次

**nvALT 的做法**：只在笔记加载时调用一次高亮。

**NV5 的问题**：
```swift
// updateNSView 同步调用（在旧内容上）
context.coordinator.applyHighlight(query: highlightQuery)

// 异步块中调用（在新内容上）
DispatchQueue.main.async {
    loadNote(...)
    applyHighlight(query: highlightQuery)
}
```

**建议修复**：移除同步调用，只在 `loadNote` 后调用一次。

---

### 问题 2：高亮缓存导致不一致

**nvALT 的做法**：没有缓存，每次都重新高亮。

**NV5 的问题**：`lastHighlightQuery` 缓存在笔记切换时导致高亮不更新。

**已修复**：在 `loadNote` 中重置 `lastHighlightQuery = ""`。

**进一步优化**：考虑完全移除缓存，像 nvALT 一样每次都重新高亮。高亮操作很快（几毫秒），缓存带来的复杂度可能不值得。

---

### 问题 3：高亮和焦点的时序耦合

**nvALT 的做法**：焦点转移（`fieldAction`）和笔记加载（`displayContentsForNoteAtIndex`）完全分离。

**NV5 的问题**：高亮和焦点都在 `updateNSView` 中，时序复杂。

**建议优化**：
```swift
// 方案 A：焦点优先，高亮延迟（不阻塞焦点）
DispatchQueue.main.async {
    loadNote(...)
    focusEditor()      // ← 焦点先
    applyHighlight()   // ← 高亮后
}

// 方案 B：高亮异步化（在后台线程计算）
DispatchQueue.global(qos: .userInitiated).async {
    let matches = findMatches(in: text, for: query)
    DispatchQueue.main.async {
        applyMatches(matches)
    }
}
```

---

### 问题 4：返回第一个匹配位置

**nvALT 的做法**：`highlightTermsTemporarilyReturningFirstRange:` 返回第一个匹配位置，用于自动选中。

**NV5 的问题**：`applyHighlight` 不返回任何值，无法自动选中第一个匹配。

**建议增强**：
```swift
func applyHighlight(query: String) -> NSRange? {
    // ... 高亮逻辑
    return firstMatchRange  // 返回第一个匹配位置
}

// 在 loadNote 后：
let firstMatch = applyHighlight(query: highlightQuery)
if let range = firstMatch, selection.length == 0 {
    textView.setSelectedRange(range)
    textView.scrollRangeToVisible(range)
}
```

---

## 立即可做的优化

### 1. 移除同步的 `applyHighlight` 调用

```swift
func updateNSView(_ nsView: NSScrollView, context: Context) {
    guard let textView = nsView.documentView as? NSTextView else { return }
    context.coordinator.parent = self

    if context.coordinator.currentNoteID != noteID {
        textView.window?.makeFirstResponder(nil)
        let shouldFocusAfterLoad = MainWindowController.shared.pendingFocusAfterLoad
        MainWindowController.shared.pendingFocusAfterLoad = false
        DispatchQueue.main.async {
            context.coordinator.commitPendingIfNeeded()
            context.coordinator.loadNote(id: noteID, body: initialBody, attributes: initialAttributes, selection: initialSelection)
            context.coordinator.applyHighlight(query: highlightQuery)  // ← 只在这里调用
            if shouldFocusAfterLoad {
                MainWindowController.shared.focusEditor()
            }
        }
    } else {
        MainWindowController.shared.pendingFocusAfterLoad = false
    }
    // 移除这行：context.coordinator.applyHighlight(query: highlightQuery)
}
```

### 2. 考虑移除高亮缓存

```swift
func applyHighlight(query: String) {
    // 移除这两行：
    // guard query != lastHighlightQuery else { return }
    // lastHighlightQuery = query
    
    guard let textView = textView,
          let layoutManager = textView.layoutManager,
          let storage = textView.textStorage,
          storage.length > 0,
          textView.window != nil else { return }
    
    // ... 高亮逻辑
}
```

### 3. 焦点优先，高亮延迟

```swift
DispatchQueue.main.async {
    context.coordinator.commitPendingIfNeeded()
    context.coordinator.loadNote(...)
    if shouldFocusAfterLoad {
        MainWindowController.shared.focusEditor()  // ← 焦点先
    }
    context.coordinator.applyHighlight(query: highlightQuery)  // ← 高亮后
}
```

---

## 总结

nvALT 的设计哲学：
1. **简单直接** — 没有复杂的缓存、状态机、异步协调
2. **同步优先** — 高亮在笔记加载后立即同步执行
3. **职责分离** — 焦点转移和笔记加载完全独立
4. **性能优化** — 使用 C 字符串、增量搜索、CoreFoundation API

NV5 应该学习的：
1. ✅ 移除不必要的缓存（或在笔记切换时重置）
2. ✅ 减少异步层级（高亮应该在 `loadNote` 后立即执行）
3. ✅ 焦点和高亮解耦（焦点优先，高亮不阻塞）
4. ⚠️ 考虑返回第一个匹配位置（用于自动选中）
