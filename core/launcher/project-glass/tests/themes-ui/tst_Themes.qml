import QtQuick
import QtTest
import "../.." as Glass

TestCase {
    id: test
    name: "ThemeRendering"
    visible: true; when: windowShown
    width: 780; height: 580
    readonly property url clipShader: Qt.resolvedUrl("../../../../build-win11/launcher/project-glass/.qsb/continuousclip.frag.qsb")
    Rectangle {
        id: preview
        anchors.fill: parent
        color: gallery.dark ? "#202125" : "#F5F5F7"
        Text { x: 24; y: 20; text: "Themes"; font.pixelSize: 22; font.bold: true; color: gallery.ink }
        Text { x: 24; y: 54; text: "Choose an official theme, or save and share your own appearance."; font.pixelSize: 13; color: gallery.muted }
        Glass.ThemeGallery {
            id: gallery
            x: 24; y: 92; width: parent.width - 48; height: implicitHeight
            themes: themeStore.themes.slice(0,4)
            selectedId: "official-aurora"
            ink: dark ? "#F7FAFF" : "#172333"
            muted: dark ? "#AAB8CC" : "#58697D"
            accent: dark ? "#65D9D1" : "#3268A8"
            clipShader: test.clipShader
            catImageFor: function(id) { return themeStore.catImage(id) }
            onSelected: function(themeId) { selectedId=themeId }
        }
        Glass.RoundedPanel {
            id: contour
            x: 24; y: 464; width: 220; height: 90; radius: 24
            color: "white"; clipShader: test.clipShader
        }
        Text { x: 264; y: 494; text: "Continuous panel contour"; color: gallery.ink; font.pixelSize: 14 }
    }
    function test_select_and_keyboard() {
        compare(themeStore.themes.length,10)
        var paper=findChild(gallery,"themeCard-official-paper")
        verify(paper!==null)
        mouseClick(paper,50,50)
        compare(gallery.selectedId,"official-paper")
        var aurora=findChild(gallery,"themeCard-official-aurora")
        aurora.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(gallery.selectedId,"official-aurora")
    }
    function test_prism_cat_previews() {
        gallery.themes=themeStore.themes.filter(function(t) { return !!t.appearance.cat })
        compare(gallery.themes.length,4)
        for (var i=0;i<gallery.themes.length;i++) {
            var card=findChild(gallery,"themeCard-"+gallery.themes[i].id)
            verify(card!==null)
            var cat=findChild(card,"prismCatPreview")
            verify(cat!==null)
            tryCompare(cat,"status",Image.Ready)
        }
        waitForRendering(preview)
        if (reviewOutput.length) grabImage(preview).save(reviewOutput+"-prism-previews.png")
        gallery.themes=Qt.binding(function() { return themeStore.themes.slice(0,4) })
    }
    function test_contour_and_screenshots() {
        gallery.dark=true
        waitForRendering(preview)
        wait(150)
        var image=grabImage(preview), scale=image.width/preview.width
        fuzzyCompare(image.pixel(Math.round(24*scale),Math.round(464*scale)).r,32/255,0.01)
        fuzzyCompare(image.pixel(Math.round(134*scale),Math.round(509*scale)).r,1,0.01)
        if (reviewOutput.length) image.save(reviewOutput+"-dark.png")
        gallery.dark=false
        waitForRendering(preview)
        wait(150)
        if (reviewOutput.length) grabImage(preview).save(reviewOutput+"-light.png")
        gallery.dark=true
    }
    function test_frontend_theme_and_sheets() {
        failOnWarning(/ReferenceError|TypeError|Binding loop|Unable to assign/)
        var component=Qt.createComponent("../../Main.qml")
        tryCompare(component,"status",Component.Ready)
        var window=component.createObject(null,{visible:true,sidebarGuideSeen:true})
        verify(window!==null,component.errorString())
        var savedId=""
        try {
            tryCompare(window,"themeReady",true)
            reviewHarness.evaluate(window,'downloadData.quickVersions=["1.21.8"]; sidebarQuickVersion="1.21.8"; glassTuning.reducedMotion=true; glassTuning.increaseContrast=true; applyTheme(themeStore.theme("official-paper"));')
            compare(window.darkMode,false)
            compare(window.appliedThemeId,"official-paper")
            verify(reviewHarness.evaluate(window,'glassTuning.reducedMotion && glassTuning.increaseContrast'))
            savedId=reviewHarness.evaluate(window,'var saved=themeStore.saveTheme({format:"vitra-theme",version:1,name:"Review theme",author:"Test",appearance:currentThemeAppearance()}); applyTheme(saved); saved.id')
            verify(savedId.length>0)
            compare(window.appliedThemeId,savedId)
            window.customAccent="#ff8800"
            tryCompare(window,"appliedThemeId","")
            themeStore.removeTheme(savedId)
            reviewHarness.evaluate(window,'applyTheme(themeStore.theme("official-prism-kitteh"))')
            compare(window.themeCat,"kitteh")
            tryVerify(function() { return reviewHarness.evaluate(window,'themeCatArtwork.status===Image.Ready && themeCatArtwork.visible') })
            captureWindow(window,"-prism-canvas.png")
            reviewHarness.evaluate(window,'themeLibraryPopup.open(); themeLibraryScroll.contentY=Math.max(0,themeGallery.implicitHeight-themeLibraryScroll.height)')
            wait(250)
            captureWindow(window,"-prism-library.png")
            reviewHarness.evaluate(window,'themeLibraryPopup.close(); applyTheme(themeStore.theme("official-aurora"))')
            compare(window.themeCat,"")
            reviewHarness.evaluate(window,'applyTheme(themeStore.theme("official-aurora")); themeLibraryPopup.open()')
            wait(250)
            captureWindow(window,"-library.png")
            reviewHarness.evaluate(window,'themeLibraryPopup.close(); canvasQuickDownload.open()')
            wait(250)
            captureWindow(window,"-quick-download.png")
            reviewHarness.evaluate(window,'canvasQuickDownload.close(); prismBridge.signingIn=true; prismBridge.loginCode="TEST1234"; loginPopup.open()')
            wait(250)
            captureWindow(window,"-login.png")
            reviewHarness.evaluate(window,'loginPopup.close(); prismBridge.signingIn=false')
            wait(300)
            if (reviewHarness.supportsWindowDrag()) {
            verify(!reviewHarness.dropFiles(window,[]),"text-only drags are ignored")
            verify(reviewHarness.dropFiles(window,["file:///C:/Games/Test%20Pack.mrpack"]),"file drag reaches the window")
            compare(reviewHarness.evaluate(window,'prismBridge.dropRequests.length'),1)
            compare(reviewHarness.evaluate(window,'prismBridge.dropRequests[0]'),"file:///C:/Games/Test Pack.mrpack")
            verify(window.packImportNotice)
            verify(reviewHarness.evaluate(window,'prismBridge.importingLocalPack'))
            captureWindow(window,"-modpack-import.png")
            reviewHarness.evaluate(window,'prismBridge.importingLocalPack=false; prismBridge.localPackImportFinished(true,"Imported")')
            compare(window.packImportMessage,"Imported")
            verify(reviewHarness.dropFiles(window,["file:///C:/Games/one.zip","file:///C:/Games/two.zip"]))
            compare(reviewHarness.evaluate(window,'prismBridge.dropRequests.length'),1)
            compare(window.packImportMessage,"Drop one modpack file at a time.")
            reviewHarness.evaluate(window,'prismBridge.importingLocalPack=true')
            verify(reviewHarness.dropFiles(window,["file:///C:/Games/other.zip"]))
            compare(reviewHarness.evaluate(window,'prismBridge.dropRequests.length'),1)
            compare(window.packImportMessage,"Finish the current installation before importing a modpack.")
            reviewHarness.evaluate(window,'prismBridge.importingLocalPack=false')
            verify(!reviewHarness.dropMoveOnly(window,["file:///C:/Games/move-only.zip"]),"move-only drags are refused")
            verify(reviewHarness.dropFilesWithShift(window,["file:///C:/Games/copy.zip"]),"shift-drag is accepted as a copy")
            compare(reviewHarness.evaluate(window,'prismBridge.dropRequests.length'),2)
            reviewHarness.evaluate(window,'prismBridge.importingLocalPack=false')
            } else {
                console.log("Window drag test skipped: Qt platform headers are unavailable")
            }
            var navigation=findChild(window,"compactNavigation")
            verify(navigation!==null)
            var navigationInput=findChild(navigation,"navigationDragArea")
            verify(navigationInput!==null)
            mouseClick(navigationInput,navigationInput.width*5/6,navigationInput.height/2)
            tryCompare(window,"activePage","Settings")
        } finally { if (savedId.length && themeStore.theme(savedId).id) themeStore.removeTheme(savedId); window.close(); window.destroy(); wait(100) }
    }
    function captureWindow(window,suffix) {
        if (!reviewOutput.length) return
        verify(reviewHarness.captureWindow(window,reviewOutput+suffix))
    }
}
