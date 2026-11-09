# Installing Kinetiq

Full download, verification and first-launch guide. The [README](../README.md#install) has the short version.

## Installing

Requires **macOS 14 or later**, on Apple Silicon or Intel. The universal DMG contains
both architectures; no Xcode, Python or terminal build is needed to run it.

### Download, install and launch

1. Download `Kinetiq-0.5.2.dmg` and `SHA256SUMS.txt` from the project's
	[v0.5.2 GitHub release](https://github.com/Invernomut0/Kinetiq/releases/tag/v0.5.2).
	If the repository is private, sign in with an account that has access.
	Choose the DMG asset, **not** GitHub's **Source code** ZIP/TAR, which has no ready-to-run app.
2. Optionally verify the download in Terminal from the folder containing both files:

	```sh
	cd ~/Downloads
	shasum -a 256 -c SHA256SUMS.txt
	```

	The DMG must report **OK**. Stop and download it again if verification fails.
	A checksum detects changed/corrupted bytes; it is not a malware-free certification.
3. Open the DMG, drag **Kinetiq.app** onto **Applications**, then eject the disk image.
	Run the installed copy, not the app inside the mounted DMG.
4. Double-click `/Applications/Kinetiq.app`. If macOS cannot verify its developer,
	follow the first-launch steps below. Once approved, you can also launch it with:

	```sh
	open "/Applications/Kinetiq.app"
	```

5. Grant **Accessibility** and **Screen Recording** in **System Settings → Privacy &
	Security** when requested. Accessibility lets Kinetiq watch drags and restore/move
	windows; Screen Recording supplies the captured pixels for effects. macOS may
	require you to quit and reopen Kinetiq after granting them. The app lives in the
	menu bar; closing its management window does not quit it. Reopen Settings from
	the menu bar, and quit from **Kinetiq → Quit**.

Analytics is optional and off by default. Since build 44, it requires **GA4 revision-3
consent** before reading/sending the configured country. Declining does not disable
effects. Installing the app does **not** enable or install the system screen saver;
that remains a separate explicit opt-in.

### First launch: why macOS may block the app

This release is **not notarized by Apple**. Its app and embedded saver have verified
local signatures, but an **ad-hoc signature is not an Apple Developer ID or notarization**.
macOS can therefore show “developer cannot be verified” or “Apple cannot check it
for malicious software”. Downloaded apps are marked with `com.apple.quarantine`,
which tells Gatekeeper to perform first-launch checks. A warning is not proof that
the app is safe—or that it is malicious.

**Recommended:** after trying to open the installed copy, go to **System Settings →
Privacy & Security**, find Kinetiq under Security and select **Open Anyway**, then
confirm **Open**. Only do this for the original release you intentionally downloaded
and verified. See [Apple's first-launch guidance](https://support.apple.com/en-us/102445).
No `xattr` command is normally necessary when this route works.

**Terminal alternative, only for that trusted copy:** if the quarantine warning still
prevents opening it, remove **only the quarantine attribute**, recursively within
this app bundle, and then open it:

```sh
xattr -dr com.apple.quarantine "/Applications/Kinetiq.app"
open "/Applications/Kinetiq.app"
```

Here `-d` deletes the named attribute and `-r` includes bundled files. The often-shared
`xattr -cr` command instead clears **all** extended attributes recursively; that is
broader than needed and can discard unrelated metadata, so it is not recommended.
Neither command notarizes the app, verifies its origin, grants Accessibility/Screen
Recording or fixes an invalid signature. An absent quarantine attribute means no
removal is needed. Do not apply these commands to `/Applications` as a whole, disable
Gatekeeper globally, or use them to ignore “will damage your computer”, revoked
authorization or a genuinely damaged/tampered app: stop and verify/re-download instead.
On managed Macs, follow your administrator's policy. If the installed copy is not
writable, use a writable app folder such as `~/Applications` and adjust the quoted
path; do not blindly run commands with elevated privileges.
