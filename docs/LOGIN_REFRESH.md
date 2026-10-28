# Aster Vale login — Android 0.49.0 (89)

The login artwork now carries a large, centered gold **Aster Vale** title with a serif font, outline and shadow. Original forest scenery fills the framed panel; the old title portion is cropped from the composition. Three native paper-doll previews show Warrior, Magician and Archer equipment from the existing item catalog. A dark gradient keeps the title readable, with gold corner ornaments and a short tagline.

The account form uses its own dark frame. The Android Remember, automatic sign-in and Forget controls fit alongside the art, with Log in, Create account and Server settings visible in the initial phone view. Server details still expand when requested. Authentication, credential storage, character selection and creation use the existing handlers.

No generated character art or replacement sprites are required. The forest and character layers remain private imported game content. DejaVu Serif Bold and its accompanying license are bundled in the client; export filters explicitly include the font notice.

## Verification

Rendered the actual Godot UI at 960×540, 1280×720 and 1544×720 with all Android credential controls visible, using synthetic UI state without opening a live player character. Inspected the title, character sprites and form placement. Existing account/login/sign tests passed 151 checks; automatic-login regression passed 16; character flow passed 153 across four landscape sizes and zero through three characters. Detailed results accompany this document.

The release report records APK signature/alignment, embedded assets and phone update verification. The phone update preserves app data; visual checks use isolated fixtures.
