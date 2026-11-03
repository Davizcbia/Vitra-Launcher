import QtQuick
import QtTest
import "../.." as Glass

TestCase {
    id: test
    name: "WindowsChromeRendering"
    // Shared controls observe the application's language revision. Supply the
    // same property in this standalone harness so labels retain their widths.
    property QtObject prismBridge: QtObject { property int languageRevision: 0 }
    when: windowShown
    visible: true
    width: 600; height: 720
    readonly property url clipShader: Qt.resolvedUrl("../../../../build-win11/launcher/project-glass/.qsb/continuousclip.frag.qsb")
    readonly property url glowShader: Qt.resolvedUrl("../../../../build-win11/launcher/project-glass/.qsb/sidebarglow.frag.qsb")
    Item {
        id: contourCapture
        width: 240; height: 180
        Rectangle { anchors.fill: parent; color: "#ff00ff" }
        Rectangle {
            id: contour
            x: 20; y: 20; width: 200; height: 140
            color: "#007aff"
            layer.enabled: true
            layer.effect: Glass.ContinuousClip { radius: 24; fragmentShader: test.clipShader }
        }
    }
    Item {
        id: glowScene
        width: 300; height: 300; visible: false
        Rectangle { width: 300; height: 150; color: "#ff163c" }
        Rectangle { y: 150; width: 300; height: 150; color: "#ff9900" }
    }
    Rectangle {
        id: rail
        y: 190; width: 240; height: 300
        color: "#202022"
        Glass.SidebarGlow {
            id: glow
            anchors.right: parent.right; width: 115; height: parent.height
            scene: glowScene; sceneLeft: 0; opacity: 0.7; shader: test.glowShader
        }
    }
    Glass.GlassNavigation {
        id: nav
        x: 20; y: 530; width: 310; height: 44
        onActivated: function(index) { currentIndex=index }
    }
    Rectangle {
        id: categoryBackdrop
        y: 580; width: 520; height: 60; color: "#34567a"
        ShaderEffectSource { id: categoryTexture; sourceItem: categoryBackdrop; visible: false; live: true }
        Glass.GlassCategoryBar {
            id: categories
            x: 8; width: implicitWidth; height: 56
            options: ["Versions", "Mods", "Shaders", "Resource packs", "Modpacks"]
            selected: "Versions"
            material: categoryGlass
            onChosen: function(value) { selected=value }
            Component {
                id: categoryGlass
                Glass.LiquidGlass {
                    surface: categories; viewport: categoryBackdrop
                    sharpTexture: categoryTexture; blurredTexture: categoryTexture
                    shader: Qt.resolvedUrl("../../../../build-win11/launcher/project-glass/.qsb/liquidglass.frag.qsb")
                    radius: 20; capsuleCount: categories.options.length
                    capsuleOne: categories.shape(0); capsuleTwo: categories.shape(1)
                    capsuleThree: categories.shape(2); capsuleFour: categories.shape(3); capsuleFive: categories.shape(4)
                    pressedCapsule: categories.lastPressedIndex; capsuleFusionProgress: categories.fusionProgress
                    fusionDistance: 48
                }
            }
        }
    }
    function test_contour_pixels() {
        waitForRendering(contourCapture)
        var img=grabImage(contourCapture)
        var scale=img.width/contourCapture.width
        function alpha(x,y) { return 255-img.red(Math.floor(x*scale),Math.floor(y*scale)) }
        compare(alpha(20,20),0,"No residual corner pixel")
        compare(alpha(21,21),0)
        compare(alpha(219,159),0)
        compare(alpha(120,80),255)
        var edgePixels=0
        for (var y=0;y<Math.floor(56*scale);++y) {
            for (var x=0;x<Math.floor(56*scale);++x) {
                var a=255-img.red(x,y)
                if (a>0 && a<255) edgePixels++
                var lx=(x+0.5)/scale-20, ly=(y+0.5)/scale-20
                if (lx>=0 && ly>=0) {
                    var qx=Math.max(0,36-lx)/36, qy=Math.max(0,36-ly)/36
                    var d=(Math.pow(qx*qx*qx+qy*qy*qy,1/3)-1)*36
                    if (d>2/scale) compare(a,0,"Pixels outside curve must be fully transparent")
                }
            }
        }
        verify(edgePixels>5,"The contour needs fractional coverage, not a binary staircase")
    }
    function test_glow_is_local_and_coloured() {
        wait(300)
        waitForRendering(rail)
        var img=grabImage(rail), s=img.width/rail.width
        function red(x,y) { return img.red(Math.floor(x*s),Math.floor(y*s)) }
        compare(red(15,70),32,"Left side stays neutral")
        compare(red(120,70),32,"No wash outside the edge region")
        verify(red(230,70)>red(160,70)+30,"Colour concentrated at the right edge")
        verify(img.green(Math.floor(230*s),Math.floor(230*s))>img.green(Math.floor(230*s),Math.floor(70*s)),"Keep vertical artwork colours")
    }
    function test_selection_drag_and_bounce() {
        nav.currentIndex=0; nav.reducedMotion=false
        wait(600)
        var start=nav.tabWidth/2, middle=nav.tabWidth*1.5
        mousePress(nav.inputArea,start,22)
        tryVerify(function() { return nav.selectionItem.width>nav.tabWidth*1.1 && nav.selectionItem.height>55 })
        mouseMove(nav.inputArea,start+25,22,30)
        mouseMove(nav.inputArea,middle+12,22,30)
        compare(nav.draggingSelection,true)
        compare(nav.currentIndex,0,"Do not switch pages before release")
        mouseRelease(nav.inputArea,middle+12,22)
        compare(nav.currentIndex,1)
        tryVerify(function() { return Math.abs(nav.selectionItem.centerPosition-middle)<0.3 })
        wait(650)
        fuzzyCompare(nav.selectionItem.width,nav.tabWidth,0.2)
        fuzzyCompare(nav.selectionItem.height,nav.height,0.2)
        nav.reducedMotion=true
        mousePress(nav.inputArea,middle,22)
        mouseMove(nav.inputArea,start,22,30)
        compare(nav.selectionItem.height,nav.height)
        mouseRelease(nav.inputArea,start,22)
        compare(nav.currentIndex,0)
        nav.reducedMotion=false
    }
    function test_unselected_tab_press() {
        nav.currentIndex=0; nav.reducedMotion=false
        wait(600)
        var target=nav.tabWidth*2.5
        mousePress(nav.inputArea,target,22)
        tryVerify(function() { return nav.selectionItem.height>55 && Math.abs(nav.selectionItem.centerPosition-target)<1 })
        compare(nav.currentIndex,0)
        mouseRelease(nav.inputArea,target,22)
        compare(nav.currentIndex,2)
    }
    function test_category_press_and_material_fusion() {
        var button=findChild(categories,"categoryButton-Versions")
        var shader=findChild(categories,"liquidGlassShader")
        verify(button!==null && shader!==null)
        tryVerify(function() { return shader.capsuleOne.z>30 && shader.capsuleTwo.z>30 })
        mousePress(button,button.width/2,button.height/2)
        tryVerify(function() { return button.scale>1.05 && categories.fusionProgress>0.9 })
        compare(shader.capsuleConfig.x,5)
        compare(shader.capsuleConfig.z,0)
        verify(shader.capsuleConfig.w>0.9)
        mouseRelease(button,button.width/2,button.height/2)
        tryVerify(function() { return categories.fusionProgress<0.01 })
        categories.fusionEnabled=false
        mousePress(button,button.width/2,button.height/2)
        fuzzyCompare(categories.fusionProgress,0,0.001)
        mouseRelease(button,button.width/2,button.height/2)
        categories.fusionEnabled=true
    }
}
