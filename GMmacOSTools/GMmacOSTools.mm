// ─────────────────────────────────────────────────────────────
//  GMMenuBar.mm – Objective-C++ (.mm) dynamic lib for GameMaker
//  ▸ Adds top-level menus
//  ▸ Adds items with caller-supplied UID         (gm_menu_add_item)
//  ▸ Adds submenu items under a parent UID       (gm_menu_add_sub_item)
//  ▸ Async-returns { id:"GM_MENU", uid:"...", title:"..." }
// ─────────────────────────────────────────────────────────────
#define gml extern "C" double

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

// ─────────────────────────────────────────────────────────────
//  0.  De-clare our runner-function pointers
// ─────────────────────────────────────────────────────────────
static int  (*YY_ds_map_create)(int n, ...)                         = nullptr;
static bool (*YY_ds_map_add_string)(int map, const char *k, const char *v) = nullptr;
static void (*YY_event_perform_async)(int map, int ev)              = nullptr;
static const int YY_EVENT_OTHER_SOCIAL = 70;

// Helper to guard against NULL in case something went wrong
#define YY_SAFE_CALL(fn, ...)  do { if (fn) fn(__VA_ARGS__); } while (0)

// ─────────────────────────────────────────────────────────────
//  1.  Runner *automatically* calls this right after dlopen()
//      (same name & signature as on Windows)
// ─────────────────────────────────────────────────────────────
extern "C" double RegisterCallbacks(
        void *pEventAsync,
        void *pCreate,
        void *pAddDouble,            // we ignore these two
        void *pAddString)
{
    YY_ds_map_create       = (int  (*)(int,...))               pCreate;
    YY_ds_map_add_string   = (bool (*)(int,const char*,const char*))pAddString;
    YY_event_perform_async = (void (*)(int,int))               pEventAsync;
    return 0;
}

//────────────────── GameMaker runner symbols (weak import) ──────────────────
extern "C" {
    __attribute__((weak_import))
    int  gml_ds_map_create(int n, ...);
    __attribute__((weak_import))
    bool gml_ds_map_add_string(int map, const char *key, const char *val);
    __attribute__((weak_import))
    void gml_event_perform_async(int map, int event_type);
}
static const int EVENT_OTHER_SOCIAL = 70;

// Track which top-level menus WE have created so we can clean them later
static NSMutableSet<NSString *> *gCustomMenuTitles;

//────────────────── Click-bridge object ──────────────────
@interface GMBridge : NSObject <NSMenuDelegate>
- (void)menuClick:(NSMenuItem *)sender;
- (void)gmShowSettings:(id)sender;
- (void)menuWillOpen:(NSMenu *)menu;
- (void)menuDidClose:(NSMenu *)menu;
@end
@implementation GMBridge
- (void)menuClick:(NSMenuItem *)sender
{
    const char *uid   = ((NSString *)sender.representedObject).UTF8String;
    const char *title = sender.title.UTF8String;

    int map = YY_ds_map_create ? YY_ds_map_create(0) : -1;
    if (map != -1)
    {
        YY_ds_map_add_string(map, "id",    "GM_MENU");
        YY_ds_map_add_string(map, "uid",   uid ?: "");
        YY_ds_map_add_string(map, "title", title);
        YY_event_perform_async(map, YY_EVENT_OTHER_SOCIAL);
    }
}

- (void)gmShowSettings:(id)sender
{
    // Forward to GameMaker like every other click
    if (YY_ds_map_create && YY_ds_map_add_string && YY_event_perform_async)
    {
        int map = YY_ds_map_create(0);
        YY_ds_map_add_string(map, "id",    "GM_MENU");
        YY_ds_map_add_string(map, "uid",   "app_settings");
        YY_ds_map_add_string(map, "title", "Settings…");
        YY_event_perform_async(map, YY_EVENT_OTHER_SOCIAL);
    }
}

- (void)menuWillOpen:(NSMenu *)menu
{
    if (YY_ds_map_create && YY_ds_map_add_string && YY_event_perform_async) {
        int map = YY_ds_map_create(0);
        YY_ds_map_add_string(map, "id",    "GM_MENU_EVENT");
        YY_ds_map_add_string(map, "event", "open");
        YY_ds_map_add_string(map, "title", menu.title.UTF8String);
        YY_event_perform_async(map, YY_EVENT_OTHER_SOCIAL);
    }
}

- (void)menuDidClose:(NSMenu *)menu
{
    if (YY_ds_map_create && YY_ds_map_add_string && YY_event_perform_async) {
        int map = YY_ds_map_create(0);
        YY_ds_map_add_string(map, "id",    "GM_MENU_EVENT");
        YY_ds_map_add_string(map, "event", "close");
        YY_ds_map_add_string(map, "title", menu.title.UTF8String);
        YY_event_perform_async(map, YY_EVENT_OTHER_SOCIAL);
    }
}
@end
static GMBridge *gBridge;                // lazy-allocated

//────────────────── Utilities ──────────────────

// Move menuItem to slot 1 (just right of App menu) on first creation
static void placeMenuItemAtIndex1(NSMenuItem *mi)
{
    NSMenu *main = NSApp.mainMenu;
    if ([main indexOfItem:mi] != 1) {
        [main removeItem:mi];
        [main insertItem:mi atIndex:1];
    }
}

// Ensure top-level menu exists and correctly placed
static NSMenu *ensureTopMenu(NSString *name)
{
    NSMenu *main = NSApp.mainMenu;
    for (NSMenuItem *it in main.itemArray)
        if ([it.title isEqualToString:name])
            return it.submenu;

    NSMenuItem *parent =
        [[NSMenuItem alloc] initWithTitle:name action:nil keyEquivalent:@""];
    parent.submenu = [[NSMenu alloc] initWithTitle:name];
    parent.submenu.autoenablesItems = NO;
    parent.submenu.delegate = gBridge;
    [main insertItem:parent atIndex:1];          // left of View
    if (!gCustomMenuTitles) gCustomMenuTitles = [NSMutableSet new];
    [gCustomMenuTitles addObject:name];          // remember we own this one
    return parent.submenu;
}

// Depth-first search for an NSMenuItem by its UID
static NSMenuItem *findItemByUID(NSMenu *menu, NSString *uid)
{
    //NSLog(@"-[findItemByUID] menu=%@ uid=%@", menu, uid);
    for (NSMenuItem *it in menu.itemArray)
    {
        if ([it.representedObject isKindOfClass:[NSString class]] &&
            [it.representedObject isEqualToString:uid])
            return it;

        if (it.hasSubmenu) {
            NSMenuItem *hit = findItemByUID(it.submenu, uid);
            if (hit) return hit;
        }
    }
    return nil;
}

static void setItemEnabled(NSMenu *menu, NSString *uid, BOOL enabled)
{
    NSMenuItem *it = findItemByUID(menu, uid);
    if (it) it.enabled = enabled;
}

// Parse strings like  "cmd+shift+s"  → key = "s", mask = ⌘|⇧
static void parseShortcutSpec(NSString *spec,
                              NSString **keyOut,
                              NSEventModifierFlags *maskOut)
{
    NSEventModifierFlags mask = 0;
    NSString *key = @"";

    NSArray *parts = [spec.lowercaseString componentsSeparatedByString:@"+"];
    for (NSString *p in parts)
    {
        if ([p isEqualToString:@"cmd"]   || [p isEqualToString:@"command"]) mask |= NSEventModifierFlagCommand;
        else if ([p isEqualToString:@"shift"])   mask |= NSEventModifierFlagShift;
        else if ([p isEqualToString:@"opt"] ||
                 [p isEqualToString:@"option"] ||
                 [p isEqualToString:@"alt"])    mask |= NSEventModifierFlagOption;
        else if ([p isEqualToString:@"ctrl"] ||
                 [p isEqualToString:@"control"]) mask |= NSEventModifierFlagControl;
        else key = p;
    }

    // Named special keys
    NSDictionary *special = @{
        @"return": @"\r",
        @"enter":  @"\r",
        @"tab":    @"\t",
        @"space":  @" ",
        @"esc":    @"\e",
        @"escape": @"\e",
        @"delete": @"\177",
        @"backspace": @"\177"
    };
    if (special[key]) key = special[key];

    *keyOut  = key;
    *maskOut = mask;
}

//────────────────── GML-visible API ──────────────────

/**
 * gm_create_menu("File");
 */
gml gm_create_menu(const char *menuTitle_c)
{
    NSString *menuTitle = [NSString stringWithUTF8String:menuTitle_c];
    dispatch_async(dispatch_get_main_queue(), ^{
        ensureTopMenu(menuTitle);
    });
    return 0;
}

/**
 * gm_menu_add_item("File", "Open…", "o", "file_open");
 *  menuTitle   – existing or new top-level menu
 *  itemTitle   – text displayed
 *  shortcut    – keyEquivalent ("" = none)
 *  uid         – unique ID you’ll get back in async event
 */
gml gm_menu_add_item(const char *menu_c,
                     const char *title_c,
                     const char *shortcut_c,
                     const char *uid_c)
{
    NSString *menuStr = [NSString stringWithUTF8String:menu_c];
    NSString *title = [NSString stringWithUTF8String:title_c];
    NSString *shortcut = [NSString stringWithUTF8String:shortcut_c];
    NSString *uid = [NSString stringWithUTF8String:uid_c];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gBridge) gBridge = [GMBridge new];
        
        NSMenu *menu = ensureTopMenu(menuStr);
        
        NSString *key;
        NSEventModifierFlags mask;
        parseShortcutSpec(shortcut, &key, &mask);
        
        NSMenuItem *it =
        [[NSMenuItem alloc] initWithTitle: title
                                   action:@selector(menuClick:)
                            keyEquivalent:key];
        it.keyEquivalentModifierMask = mask;
        it.target            = gBridge;
        it.representedObject = uid;
        
        [menu addItem:it];
    });
    return 0;
}

/**
 * gm_menu_add_sub_item("file_open", "Recent 1", "", "recent1");
 *  parentUID – UID of an existing item; that item gains a submenu (">")
 *  Other params identical to gm_menu_add_item
 */
gml gm_menu_add_sub_item(const char *parentUID_c,
                         const char *title_c,
                         const char *shortcut_c,
                         const char *uid_c)
{
    NSString *menuStr = [NSString stringWithUTF8String:parentUID_c];
    NSString *title = [NSString stringWithUTF8String:title_c];
    NSString *shortcut = [NSString stringWithUTF8String:shortcut_c];
    NSString *uid = [NSString stringWithUTF8String:uid_c];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gBridge) gBridge = [GMBridge new];
        
        NSString *puid = menuStr;
        NSMenuItem *parent = findItemByUID(NSApp.mainMenu, puid);
        if (!parent) return;                   // parent not found
        
        if (!parent.submenu) {                  // create submenu lazily
            parent.submenu = [[NSMenu alloc] initWithTitle:parent.title];
            parent.submenu.autoenablesItems = NO;
        }
        
        NSString *key;
        NSEventModifierFlags mask;
        parseShortcutSpec(shortcut, &key, &mask);
        
        NSMenuItem *child =
        [[NSMenuItem alloc] initWithTitle:title
                                   action:@selector(menuClick:)
                            keyEquivalent:key];
        child.keyEquivalentModifierMask = mask;
        child.target            = gBridge;
        child.representedObject = uid;
        
        [parent.submenu addItem:child];
    });
    return 0;
}

//────────────────── remove by UID ──────────────────
static BOOL removeItemByUID(NSMenu *menu, NSString *uid)
{
    for (NSMenuItem *it in menu.itemArray)
    {
        // Match?
        if ([it.representedObject isKindOfClass:[NSString class]] &&
            [it.representedObject isEqualToString:uid])
        {
            [menu removeItem:it];
            return YES;
        }
        // Recurse into submenus
        if (it.hasSubmenu && removeItemByUID(it.submenu, uid))
        {
            // Clean up: if parent submenu becomes empty, you may optionally remove it:
            // if (it.submenu.numberOfItems == 0) [menu removeItem:it];
            return YES;
        }
    }
    return NO;
}

/**
 * gm_menu_remove_item("recent1");
 *  uid – UID passed when you created the item
 */
gml gm_menu_remove_item(const char *uid_c)
{
    NSString *uid = [NSString stringWithUTF8String:uid_c];
    dispatch_async(dispatch_get_main_queue(), ^{
        removeItemByUID(NSApp.mainMenu, uid);
    });
    return 0;
}

/**  gm_menu_clear_custom();
 *   Removes ONLY the menus originally created by gm_create_menu().
 *   Leaves View / Edit / Window / Help, etc. untouched.
 */
gml gm_menu_clear_custom()
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gCustomMenuTitles) return;
        
        NSMenu *main = NSApp.mainMenu;
        // Walk backwards so indices stay valid while removing
        for (NSInteger i = main.numberOfItems - 1; i >= 1; --i) {
            NSMenuItem *it = [main itemAtIndex:i];
            if ([gCustomMenuTitles containsObject:it.title]) {
                [main removeItemAtIndex:i];
            }
        }
        [gCustomMenuTitles removeAllObjects];
    });
    return 0;
}

gml gm_menu_set_enabled(const char *uid_c, double enableFlag)
{
    NSString *uid = [NSString stringWithUTF8String:uid_c];
    dispatch_async(dispatch_get_main_queue(), ^{
        setItemEnabled(NSApp.mainMenu, uid, enableFlag != 0);
    });
    return 0;
}

gml gm_menu_set_icon(const char *uid_c,
                     const char *img_c)
{
    NSString *uid = [NSString stringWithUTF8String:uid_c];
    NSString *imgStr = [NSString stringWithUTF8String:img_c];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMenuItem *it = findItemByUID(NSApp.mainMenu, uid);
        if (!it) return;
        
        NSImage *img = nil;
        
        // 1.  Try SF Symbol name (macOS 11+)
        if (@available(macOS 11.0, *)) {
            img = [NSImage imageWithSystemSymbolName:imgStr
                            accessibilityDescription:nil];
        }
        // 2.  Try bundle-resource name
        if (!img)
            img = [NSImage imageNamed:imgStr];
        // 3.  Try absolute path
        if (!img && [imgStr hasPrefix:@"/"])
            img = [[NSImage alloc] initWithContentsOfFile:imgStr];
        
        if (!img) return;                       // couldn’t resolve
        
        it.image = img;
    });
    return 0;
}

/*─────────────────────────────────────────────────────────────
  gm_menu_add_separator(menuTitle [, index])

  Works for both top-level menus and any submenu UID.
  • If menuTitle matches a *top-level* menu we insert there.
  • If it matches a UID (representedObject) we insert inside its submenu.
──────────────────────────────────────────────────────────────*/
gml gm_menu_add_separator(const char *target_c, double indexOpt /* = -1 */)
{
    NSString *target = [NSString stringWithUTF8String:target_c ?: ""];
    dispatch_async(dispatch_get_main_queue(), ^{
        // Stable NSString copy
        NSInteger idx    = (NSInteger)indexOpt;
        
        // 1) Try top-level menu first
        NSMenu *menu = nil;
        for (NSMenuItem *it in NSApp.mainMenu.itemArray)
            if ([it.title isEqualToString:target]) { menu = it.submenu; break; }
        
        // 2) If not found, treat target as UID and look for submenu
        if (!menu) {
            NSMenuItem *parent = findItemByUID(NSApp.mainMenu, target);
            if (!parent) return;                       // nothing to do
            if (!parent.submenu)
                parent.submenu = [[NSMenu alloc] initWithTitle:parent.title];
            menu = parent.submenu;
        }
        
        // Clamp index
        if (idx < 0 || idx > menu.numberOfItems)
            idx = menu.numberOfItems;
        
        [menu insertItem:[NSMenuItem separatorItem] atIndex:idx];
    });
    return 0;
}

/*─────────────────────────────────────────────────────────────
  gm_submenu_add_separator(parentUID           [, index])
  
  parentUID  – UID of the item whose submenu you’re targeting
  index      – optional position inside that submenu
               • -1 or omitted  → append at end
               • 0              → very top
               • 1              → after first item, etc.
──────────────────────────────────────────────────────────────*/
gml gm_submenu_add_separator(const char *parentUID_c,
                             double indexOpt /* = -1 */)
{
    NSString *puid = [NSString stringWithUTF8String:parentUID_c];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMenuItem *parent = findItemByUID(NSApp.mainMenu, puid);
        if (!parent) return;                         // no such UID
        
        // Create submenu lazily if caller didn't yet add any child items
        if (!parent.submenu)
            parent.submenu = [[NSMenu alloc] initWithTitle:parent.title];
        
        NSMenu *sub = parent.submenu;
        NSInteger idx = (NSInteger)indexOpt;
        if (idx < 0 || idx > sub.numberOfItems) idx = sub.numberOfItems;
        
        [sub insertItem:[NSMenuItem separatorItem] atIndex:idx];
    });
    return 0;
}

/* Call this once after RegisterCallbacks has run */
gml gm_enable_system_settings_menu()
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1) Locate the Application menu – it’s the first top-level item (index 0)
        NSMenuItem *appMenuItem = [NSApp.mainMenu itemAtIndex:0];
        if (!appMenuItem) return;
        
        // 2) Look for “Settings…” (Ventura) or “Preferences…”
        NSMenuItem *settings = nil;
        for (NSMenuItem *it in appMenuItem.submenu.itemArray)
            if ([it.title hasPrefix:@"Settings"] || [it.title hasPrefix:@"Preferences"]) {
                settings = it; break;
            }
        if (!settings) return;
        
        // 3) Point it at our bridge and enable it
        if (!gBridge) gBridge = [GMBridge new];            // existing bridge object
        settings.target  = gBridge;
        settings.action  = @selector(gmShowSettings:);      // we add this next
        settings.enabled = YES;                             // gray → black
        
    });
    return 0;
}

@interface NSObject (GMNoAutoQuit)
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app;
@end

@implementation NSObject (GMNoAutoQuit)
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
    return NO;           // ← do NOT quit after red-x
}
@end

/*─────────────────────────────────────────────────────────────*
 * gm_window_set_unsaved(path_or_nil, dirtyFlag)
 *   flag = 1  → show unsaved dot
 *   flag = 0  → hide dot
 *   Works on the game’s main window.
 *─────────────────────────────────────────────────────────────*/
gml gm_window_set_unsaved(const char *path_c, double dirtyFlag, const char *unsaved_str_c)
{
    const char *p = path_c;                        // raw pointer from GM
    NSString  *path = nil;                         // default: no document

    if (p && p[0]) {                               // non-NULL and non-empty
        path = [NSString stringWithUTF8String:p];  // safe
    }
    NSString *unsaved_str = [NSString stringWithUTF8String:unsaved_str_c];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow *w = NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.windows.firstObject;
        if (!w) return;
        NSURL *url = nil;
        if (path != nil) {
            url = [NSURL fileURLWithPath:path];
        }
        if (path && path.length > 0)          // ⭠ must be YES
        {
            w.representedURL = url;          // makes the proxy icon solid & draggable
            w.documentEdited = dirtyFlag;    // optional: “— Edited” / filled close-button
            w.title          = path.lastPathComponent;          // shows file name
        }
        else
        {
            w.representedURL = nil;          // icon stays blank
            w.documentEdited = dirtyFlag;
            w.title          = unsaved_str;          // shows file name
        }
    });
    return 0;
}

/*─────────────────────────────────────────────────────────────*
 * gm_share(path_or_text, isFileFlag)
 *
 * path_or_text  • If isFileFlag == 1  → treated as *file path*
 *               • If isFileFlag == 0  → treated as *plain text*
 *
 * Example GML:
 *     gm_share("C:/screenshots/score.png", 1);   // share a file
 *     gm_share("I just beat Level 5!",     0);   // share text
 *
 * Works from both VM & YYC, sandbox-safe (no extra entitlements).
 *─────────────────────────────────────────────────────────────*/
gml gm_share(const char *str_c, double isFile)
{
    if (!str_c) return 0;

    /* 1) Convert once, outside the block */
    NSString *src = [NSString stringWithUTF8String:str_c];

    dispatch_async(dispatch_get_main_queue(), ^{
        id item = nil;
        if (isFile != 0) {
            // file → NSURL
            item = [NSURL fileURLWithPath:src];
        } else {
            // plain text
            item = src;
        }
        if (!item) return;

        /* 2) Build and show the system picker */
        NSSharingServicePicker *picker =
            [[NSSharingServicePicker alloc] initWithItems:@[item]];

        // Anchor: centre of main window’s content view
        NSWindow *w = NSApp.keyWindow ?: NSApp.mainWindow;
        NSView   *view = w.contentView;
        NSRect    rect = NSMakeRect(view.bounds.size.width * 0.5,
                                    view.bounds.size.height * 0.5,
                                    1, 1);

        [picker showRelativeToRect:rect
                             ofView:view
                      preferredEdge:NSMinYEdge];
    });
    return 0;
}

@interface NSObject (NBSOpen)
- (BOOL)application:(NSApplication *)app
           openFile:(NSString *)path;            // single file
- (void)application:(NSApplication *)app
          openFiles:(NSArray<NSString*> *)paths; // multiple files
@end

@implementation NSObject (NBSOpen)
- (BOOL)application:(NSApplication *)app openFile:(NSString *)p
{
    [self application:app openFiles:@[p]];
    return YES;                                  // tell macOS we handled it
}

- (void)application:(NSApplication *)app openFiles:(NSArray<NSString*> *)paths
{
    if (!YY_ds_map_create) return;               // dylib not yet patched

    for (NSString *p in paths)
    {
        int m = YY_ds_map_create(0);
        YY_ds_map_add_string(m, "id",   "FILE_OPEN");
        YY_ds_map_add_string(m, "path", p.UTF8String);
        YY_event_perform_async(m, YY_EVENT_OTHER_SOCIAL);
    }
    [app activateIgnoringOtherApps:YES];         // bring window to front
}
@end

/* ---------- tiny helpers to load / save the plist in Application Support --- */
static NSString *PlistPath(void)
{
    NSURL *appSup = [[[NSFileManager defaultManager]
        URLsForDirectory:NSApplicationSupportDirectory
               inDomains:NSUserDomainMask] firstObject];

    NSURL *dir = [appSup URLByAppendingPathComponent:
                 [[NSBundle mainBundle] bundleIdentifier] ?: @"App"];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir
                          withIntermediateDirectories:YES
                                           attributes:nil error:nil];
    return [[dir URLByAppendingPathComponent:@"bookmarks.plist"].path copy];
}
static NSMutableDictionary<NSString*, NSData*> *BookDict(void)
{
    static NSMutableDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        /* try to read the on-disk plist */
        d = [[NSMutableDictionary alloc] initWithContentsOfFile:PlistPath()];
        if (!d) d = [NSMutableDictionary new];          // fallback if file missing
    });
    return d;
}
static void Save(void) { [BookDict() writeToFile:PlistPath() atomically:YES]; }

/* ----------  gml bookmark_store(pathOrURL, key, readOnlyFlag) -------------- */
gml bookmark_store(const char *path_c, const char *key_c, double readOnly)
{
    if (!path_c || !key_c) return 0;

    NSString *key  = [NSString stringWithUTF8String:key_c];
    NSString *str  = [NSString stringWithUTF8String:path_c];

    NSURL *url = [str hasPrefix:@"file://"]
               ? [NSURL URLWithString:str]          // already a file URL
               : [NSURL fileURLWithPath:str];       // plain path

    if (!url.isFileURL) return 0;                   // refuse http:// etc.

    NSURLBookmarkCreationOptions opt =
        NSURLBookmarkCreationWithSecurityScope |
        (readOnly ? NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess : 0);

    NSData *bm = [url bookmarkDataWithOptions:opt
             includingResourceValuesForKeys:nil
                              relativeToURL:nil
                                      error:nil];
    if (!bm) return 0;

    BookDict()[key] = bm; Save();
    return 1;
}

/* ----------  gml bookmark_begin(key)  → 1/0 ------------------------------- */
gml bookmark_begin(const char *key_c)
{
    NSString *key = key_c ? [NSString stringWithUTF8String:key_c] : @"default";
    NSData *bm = BookDict()[key]; if (!bm) return 0;

    BOOL stale = NO; NSError *err = nil;
    NSURL *url = [NSURL URLByResolvingBookmarkData:bm
                                           options:NSURLBookmarkResolutionWithSecurityScope
                                     relativeToURL:nil
                               bookmarkDataIsStale:&stale
                                             error:&err];
    if (!url) return 0;
    if (stale)                                      // refresh for next time
        if (NSData *nb = [url bookmarkDataWithOptions:
                          NSURLBookmarkCreationWithSecurityScope
        includingResourceValuesForKeys:nil relativeToURL:nil error:nil])
            { BookDict()[key]=nb; Save(); }

    return [url startAccessingSecurityScopedResource] ? 1 : 0;
}

/* ----------  gml bookmark_end(key)  --------------------------------------- */
gml bookmark_end(const char *key_c)
{
    NSString *key = key_c ? [NSString stringWithUTF8String:key_c] : @"default";
    NSData *bm = BookDict()[key]; if (!bm) return 0;

    BOOL stale = NO;
    NSURL *url = [NSURL URLByResolvingBookmarkData:bm
                                           options:NSURLBookmarkResolutionWithSecurityScope
                                     relativeToURL:nil
                               bookmarkDataIsStale:&stale
                                             error:nil];
    if (!url) return 0;
    [url stopAccessingSecurityScopedResource];
    return 1;
}

/* ---------- queue for pending URLs (lives inside the dylib) ---------- */
static NSMutableArray<NSString*> *gURLQueue;
static inline void enqueueURLs(NSArray<NSURL*> *urls) {
    if (!gURLQueue) gURLQueue = [NSMutableArray new];
    for (NSURL *u in urls) {
        if (!u) continue;
        // (optional) filter scheme:
        //if (![[u.scheme lowercaseString] isEqualToString:@"nbs"]) continue;
        [gURLQueue addObject:u.absoluteString ?: @""];
    }
}

/* ---------- catch URL-opens via a category on the app delegate -------- */
@interface NSObject (GMURLSchemeOpen)
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL*> *)urls;
@end

@implementation NSObject (GMURLSchemeOpen)
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL*> *)urls
{
    if (!gURLQueue) gURLQueue = [NSMutableArray new];

    for (NSURL *u in urls) {
        if (!u) continue;

        NSURL *std = [u URLByStandardizingPath];          // normalize ./.. etc.
        NSString *readable = nil;

        if (std.isFileURL) {
            // Files → POSIX path (already percent-decoded)
            readable = std.path;
        } else {
            // Non-file schemes → percent-decoded for readability
            NSString *raw = std.absoluteString ?: @"";
            readable = raw;
            // If you want '+' to show as space in queries, uncomment:
            // readable = [readable stringByReplacingOccurrencesOfString:@"+" withString:@" "];
        }

        [gURLQueue addObject:readable ?: @""];
    }

    [app activateIgnoringOtherApps:YES];  // bring to front
}
@end

/* ---------- externs for GML to poll without callbacks ---------------- */

/* Pop one URL from the queue; returns "" if empty */
extern "C" __attribute__((visibility("default")))
const char* gm_url_take_pending(void)
{
    static NSString *ret = nil;
    if (!gURLQueue || gURLQueue.count == 0) {
        ret = @"";
    } else {
        ret = gURLQueue.firstObject;
        [gURLQueue removeObjectAtIndex:0];
    }
    return ret.UTF8String;  // GM copies immediately
}

/* Optional: how many are queued */
extern "C" __attribute__((visibility("default")))
double gm_url_pending_count(void)
{
    return gURLQueue ? (double)gURLQueue.count : 0.0;
}

/* Optional but nice: ensure queue exists as soon as the dylib loads */
__attribute__((constructor))
static void GMURL_init(void) { gURLQueue = [NSMutableArray new]; }
