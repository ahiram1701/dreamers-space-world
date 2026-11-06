; Instalador de Dreamer's Space World para Windows (NSIS 3).
;   makensis -DVERSION=0.6.6 -DSRC=build/windows -DOUT=DreamersSpaceWorld-Setup-v0.6.6.exe installer/DreamersSpaceWorld.nsi
; Se instala por usuario (sin pedir administrador) en %LOCALAPPDATA%\Programs, para que el
; actualizador del juego pueda reemplazar sus archivos. Crea accesos en Inicio (y, si quieres,
; en el escritorio) y aparece en «Aplicaciones instaladas» para desinstalarlo.
; Las partidas viven en %APPDATA%\Godot\app_userdata y solo se borran si lo marcas al desinstalar.

Unicode true
!include "MUI2.nsh"

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef NUMVER
  !define NUMVER "${VERSION}"
!endif
!ifndef SRC
  !define SRC "..\build\windows"
!endif
!ifndef OUT
  !define OUT "DreamersSpaceWorld-Setup.exe"
!endif

!define APP "Dreamer's Space World"
!define EXE "DreamersSpaceWorld.exe"
!define KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\DreamersSpaceWorld"
!define SAVES "$APPDATA\Godot\app_userdata\Dreamer's Space World"

Name "${APP}"
OutFile "${OUT}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "${KEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "${APP} ${VERSION}"

VIProductVersion "${NUMVER}.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "FileDescription" "Instalador de ${APP}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "CompanyName" "ahiram1701"
VIAddVersionKey "LegalCopyright" "(c) 2026 ahiram1701"

!define MUI_ICON "..\assets\brand\icon.ico"
!define MUI_UNICON "..\assets\brand\icon.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Bienvenido/a a ${APP}"
!define MUI_WELCOMEPAGE_TEXT "Vas a instalar ${APP} ${VERSION}.$\r$\n$\r$\nSe instala solo para tu usuario y no necesita permisos de administrador. El juego se actualiza solo cuando sale una versión nueva."
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Abrir ${APP}"
!define MUI_COMPONENTSPAGE_NODESC

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_COMPONENTS
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Spanish"

Section "${APP} (necesario)" SecGame
  SectionIn RO
  SetOutPath "$INSTDIR"
  File /r "${SRC}\*.*"
  WriteUninstaller "$INSTDIR\Desinstalar.exe"
  CreateDirectory "$SMPROGRAMS\${APP}"
  CreateShortcut "$SMPROGRAMS\${APP}\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
  CreateShortcut "$SMPROGRAMS\${APP}\Desinstalar ${APP}.lnk" "$INSTDIR\Desinstalar.exe"
  WriteRegStr HKCU "${KEY}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${KEY}" "Publisher" "ahiram1701"
  WriteRegStr HKCU "${KEY}" "DisplayIcon" "$INSTDIR\${EXE}"
  WriteRegStr HKCU "${KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${KEY}" "UninstallString" '"$INSTDIR\Desinstalar.exe"'
  WriteRegStr HKCU "${KEY}" "QuietUninstallString" '"$INSTDIR\Desinstalar.exe" /S'
  WriteRegStr HKCU "${KEY}" "URLInfoAbout" "https://github.com/ahiram1701/dreamers-space-world"
  WriteRegDWORD HKCU "${KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${KEY}" "NoRepair" 1
SectionEnd

Section "Acceso directo en el escritorio" SecDesktop
  CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\${APP}.lnk"
  RMDir /r "$SMPROGRAMS\${APP}"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "${KEY}"
SectionEnd

Section /o "un.Borrar también mis partidas y ajustes" SecSaves
  RMDir /r "${SAVES}"
SectionEnd
