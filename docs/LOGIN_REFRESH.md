# Aster Vale login — Android 0.49.2 (91)

The login artwork now carries a large, centered gold **Aster Vale** title with a serif font, outline and shadow. The complete original login picture fills the framed panel, including its original border and Endless Online logo. It is rendered from the full texture without cropping. A lighter gradient preserves the original artwork beneath the new centered title. Six smooth illustrated portraits show Warrior, Magician, Archer, Rogue, Priest and Summoner, based on the exact native outfits previously shown here. The built-in image-generation tool refined their faces, hair, materials and equipment while preserving class colours and identities. Gold corner ornaments and a short tagline complete the panel.

The account form uses its own dark frame. The Android Remember, automatic sign-in and Forget controls fit alongside the art, with Log in, Create account and Server settings visible in the initial phone view. Server details still expand when requested. Authentication, credential storage, character selection and creation use the existing handlers.

The login-only portrait atlas lives in private local content at `client/content/ui/login-class-portraits-v1.png`. It contains three columns and two rows in Warrior/Magician/Archer then Rogue/Priest/Summoner order, with transparency. Atlas clipping, linear filtering and mipmaps keep the small portraits smooth. The login falls back to native paper-doll previews when the portrait asset is absent. World sprites and character-selection equipment previews use the existing native artwork. The original background remains private imported game content. DejaVu Serif Bold and its accompanying license are bundled in the client; export filters explicitly include the font notice.

## Verification

Rendered the actual Godot UI at 960×540, 1280×720 and 1544×720 with all Android credential controls visible, using synthetic UI state without opening a live player character. Inspected the title, character sprites and form placement. For the underlying 0.49.0 login flow, account/login/sign tests passed 151 checks; automatic-login regression passed 16; character flow passed 153 across four landscape sizes and zero through three characters. Detailed results accompany this document.

The release report records APK signature/alignment, embedded assets and phone update verification. The phone update preserves app data; visual checks use isolated fixtures.

The 0.49.1 correction restores the full original artwork after the initial refresh cropped away its logo and border. The six-character lineup and all saved-login controls were rendered and inspected at 960×540, 1280×720 and 1544×720. No image asset was edited.

## Illustrated portraits in 0.49.2

A Godot reference renderer composed the six existing outfits at a larger scale on transparent background. Built-in `image_gen` edit mode produced a refined painted lineup, then arranged it into a 3×2 atlas with cleaner alpha edges. The final 1536×1024 RGBA image remains alongside private original content and is bundled in local exports. The exact prompts are in [LOGIN_PORTRAITS_PROMPTS.md](LOGIN_PORTRAITS_PROMPTS.md).

Both Android saved-login controls and the simpler desktop form were rendered at 960×540, 1280×720 and 1544×720. The artwork panel minimum height increases to 460 logical pixels so the title, tagline and portraits have room in the shorter form. Release verification is recorded in `login-portraits-release-report.json`.
