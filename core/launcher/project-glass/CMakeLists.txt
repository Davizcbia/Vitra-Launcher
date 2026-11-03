find_package(Qt6 6.8 REQUIRED GLOBAL COMPONENTS Qml Quick QuickControls2 ShaderTools)
target_compile_definitions(Launcher_logic PRIVATE PROJECTGLASS_NATIVE_FRONTEND)
# windows.h must not define min/max: Qt headers follow it in the moc bundle.
target_compile_definitions(${Launcher_Name} PRIVATE $<$<PLATFORM_ID:Windows>:NOMINMAX>)
target_sources(${Launcher_Name} PRIVATE Frontend.cpp PrismBridge.h InstanceSync.h SyncFiles.h ThemeStore.h ThemeStore.cpp InstanceEditorFiles.h ModrinthInstallTask.h ModpackDrop.h MacWindowMetrics.h ScreenColorPicker.h PgTranslate.h MemoryOptimizer.h LaunchDiagnosis.h)
target_include_directories(${Launcher_Name} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(${Launcher_Name} PRIVATE Qt6::Quick Qt6::QuickControls2)
if(APPLE)
    target_sources(${Launcher_Name} PRIVATE MacWindow.mm NativeCanvas.inc NativePages.inc NativeDownloadRow.inc)
    set_source_files_properties(MacWindow.mm PROPERTIES COMPILE_FLAGS "-fobjc-arc")
    target_link_libraries(${Launcher_Name} PRIVATE "-framework Cocoa" "-framework QuartzCore")
endif()
qt_add_qml_module(${Launcher_Name} URI ProjectGlass VERSION 1.0 RESOURCE_PREFIX /qt/qml NO_GENERATE_QMLTYPES
    QML_FILES Main.qml RoundedPanel.qml ThemeGallery.qml ContinuousClip.qml SidebarGlow.qml GlassNavigation.qml GlassCategoryBar.qml LiquidGlass.qml GlassTuning.qml GlassLab.qml DownloadData.qml DownloadLogic.js CanvasLayout.js InstanceData.js)

# Windows Liquid Glass: the same shader the Glass Lab hot-reloads from shaders/.
if(WIN32)
    # DWM corner/border attributes for the frameless window chrome (Frontend.cpp).
    target_link_libraries(${Launcher_Name} PRIVATE dwmapi)
    qt_add_shaders(${Launcher_Name} pg_liquid_glass
        PREFIX "/pgshaders" BASE "shaders"
        FILES shaders/liquidglass.frag)
endif()

qt_add_shaders(${Launcher_Name} pg_contours
    PREFIX "/pgshaders" BASE "shaders"
    FILES shaders/continuousclip.frag shaders/sidebarglow.frag)

if(APPLE)
    target_compile_options(${Launcher_Name} PRIVATE "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")
endif()

qt_add_resources(${Launcher_Name} project_glass_art PREFIX "/qt/qml/ProjectGlass" FILES
    # Interface translation, built by translation/build_translations.py.
    i18n/projectglass_zh_CN.qm
    assets/version-grass.png
    assets/default-account.svg
    assets/default-fabric.svg
    assets/default-forge.png
    assets/default-neoforge.svg
    assets/default-quilt.svg
    assets/default-vanilla.png
    assets/test-adventure.svg
    assets/test-builders.svg
    assets/test-creative.svg
    assets/test-explorer.svg
    assets/test-fabric.svg
    assets/test-factory.svg
    assets/test-hardcore.svg
    assets/test-legacy.svg
    assets/test-neoforge.svg
    assets/test-quilt.svg
    assets/test-rebirth.svg
    assets/test-redstone.svg
    assets/test-skyblock.svg
    assets/test-vanilla.svg
    # SF Symbols stand-ins for platforms without AppKit (see Frontend.cpp).
    assets/symbols/arrow.down.circle.svg
    assets/symbols/arrow.down.svg
    assets/symbols/arrow.down.to.line.svg
    assets/symbols/chevron.down.svg
    assets/symbols/chevron.right.svg
    assets/symbols/chevron.up.svg
    assets/symbols/chevron.up.chevron.down.svg
    assets/symbols/folder.svg
    assets/symbols/gearshape.svg
    assets/symbols/link.svg
    assets/symbols/magnifyingglass.svg
    assets/symbols/person.crop.circle.svg
    assets/symbols/play.fill.svg
    assets/symbols/sidebar.left.svg
    assets/symbols/xmark.svg
    assets/symbols/exclamationmark.triangle.fill.svg
    assets/symbols/arrow.uturn.backward.svg
    assets/symbols/bolt.fill.svg
    assets/symbols/circle.lefthalf.filled.svg
    assets/symbols/cpu.svg
    assets/symbols/doc.on.clipboard.svg
    assets/symbols/doc.on.doc.svg
    assets/symbols/list.bullet.svg
    assets/symbols/memorychip.svg
    assets/symbols/paintpalette.svg
    assets/symbols/photo.svg
    assets/symbols/questionmark.circle.svg
    assets/symbols/sparkles.svg
    assets/symbols/square.grid.2x2.svg
    assets/symbols/checkmark.svg
    assets/symbols/chevron.left.svg
    assets/symbols/stop.fill.svg
    assets/symbols/wifi.slash.svg
    assets/symbols/menubar.rectangle.svg
    assets/symbols/eyedropper.svg
    assets/symbols/checkmark.white.svg
    assets/symbols/chevron.up.chevron.down.white.svg
)
