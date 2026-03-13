# unActivationLock
A tool for helping prevent user-based Activation Lock issues.
<img src="images/activationunlock_light.png" img align="left" width=30%>

This script checks to see if a machine is Activation locked, and if so, it will try to determine if the currently logged in user is the one associated with the activation lock, and prompt the user to turn off Find My Mac. If the device is enrolled in an MDM, this will give that MDM solution enough time to prevent future Activation Lock and gather an Activation Lock bypass code should the Activation Lock ever get turned back on. There is also an option to *always* prompt a user to log out of Find My Mac regardless of Activation Lock status.

This script is designed to assist with *existing* devices that were enrolled into an MDM when a user on the device is already logged into iCloud with Find My Mac enabled at the time of enrollment. To prevent activation lock on NEW enrollments, I **highly suggest** you enroll your devices using Automated Device Enrollment. That is the best way to avoid activation lock from happening in the first place. You can find more thoughts around user-based Activation Lock over on the [blog](https://www.macosadventures.com/2023/01/30/a-guide-to-disabling-preventing-icloud-activation-lock).

This script has been tested on macOS Monterey through macOS Sequoia (15.x) on both Apple Silicon and Intel Macs.

## What's New in V2.0

- **Kandji Passport support** — handles account renames where the console username no longer matches the original local account (e.g. `jsmith` → `JSmith@company.com`)
- **Updated instruction messaging** — step-by-step dialog messages tailored to macOS 14 and macOS 15, so users know exactly where to go in System Settings
- **Reliable plist parsing** — rewrote Find My Mac detection to iterate services with PlistBuddy instead of fragile `grep`/`awk` parsing
- **system_profiler as source of truth** — the `Enabled` field in `MobileMeAccounts.plist` is unreliable; Activation Lock status from `system_profiler` is now the authoritative signal
- **macOS version-aware System Settings** — automatically opens the correct iCloud preference pane for macOS 13+
- **Improved logging** — timestamped log entries with consistent formatting

## Deploying with Kandji

### 1. Identify Activation-Locked Devices with Prism

Use [Prism](https://support.kandji.io/support/solutions/articles/72000600794-prism) to find devices with user-based Activation Lock enabled:

1. In Kandji, navigate to **Prism**
2. Filter for **Activation Lock Status → Enabled**
3. Review the results — these are the devices that need remediation

### 2. Create the Custom Script in Kandji

1. Go to **Library → Add New → Custom Script**
2. Set the script interpreter to **Zsh**
3. Paste the contents of `unActivationLock.zsh` into the script body
4. Set the run cadence based on your needs (e.g. every 15 minutes, once per day)
5. Save the library item

### 3. Scope with Iru Using an Assignment Map

Use [Iru](https://iru.dev) to scope the script only to devices that actually need it:

1. In Iru, create a tag called **`activation-locked`**
2. Apply the `activation-locked` tag to the devices identified in Prism
3. In your Iru Assignment Map, create a block that scopes the custom script library item to devices with the `activation-locked` tag
4. As devices successfully disable Find My Mac, remove the tag to stop the script from running

This keeps the script targeted to only the machines that need remediation rather than running fleet-wide.

## Customizing the Dialog

While this script was designed with Kandji in mind, it is designed to be plug-and-play for just about any MDM.

Three options for messaging the end-user are included: the Kandji CLI, SwiftDialog, or standard osascript. Feel free to add your messaging binary of choice if you prefer using your native MDM messaging system or a different third party tool.

You can customize the app icon used in the dialog. Deploy your own custom icon or use one that already exists on the machine. A few suggestions:

`/System/Library/PrivateFrameworks/AOSUI.framework/Versions/A/Resources/AppleID.icns`
`/System/Library/PrivateFrameworks/AOSUI.framework/Versions/A/Resources/findmy.icns`
`/System/Library/PrivateFrameworks/AOSUI.framework/Versions/A/Resources/iCloud.icns`

The FindMy icon is set as the default, since it helps the end-user visually identify the section of System Settings they need.

**Pro Tip:** osascript dialogs look pretty boring and dated these days in macOS, but adding a path to an app icon goes a long ways towards making it look less terrible.

![](images/screenshot.png)

## Troubleshooting
* **Reading the Logs**
  * You probably have logs from the script in your MDM, but if you need to grab them locally on a machine you can grep them out of the unified log: `log show --style compact --process "logger" | grep "UnActivationLock"`
* **Run the script as zsh**
  * The most common issue people run into is running the script as bash rather than zsh. Zsh has been the default shell on macOS since 10.15 Catalina. If your MDM does not support running scripts as zsh, reach out to them and request support — zsh has been the default since October 2019.
* **Passport renamed accounts**
  * If you use Kandji Passport and the console username doesn't match the original local account name, V2.0 handles this automatically. The script will log a note about the mismatch and still prompt the current user.

## FAQ
* **Does this work for both Manual and ADE enrollments?**
  * Yes. Either way, if your MDM supports it, the default MDM behavior should be to DISALLOW user-based Activation Lock. The important part is that it *prevents* a device from becoming activation locked — it can't undo an Activation Lock already in place. Enrolling via ADE is the BEST way to ensure the "disallow Activation Lock" key is in place before the user turns on Find My Mac.
* **What happens if someone turns Find My Mac back on after disabling it?**
  * The device will continue to NOT be activation locked, assuming the MDM laid down the `Disallow Activation Lock` key.
* **What if the device was activation locked by the MDM?**
  * Device-based Activation Lock only applies to iOS and iPadOS devices.
* **What if I have multiple users?**
  * The script accounts for that and reports which user caused the Activation Lock.
* **Is there any way for a user to reactivate the activation lock after I've successfully disabled it?**
  * If the device was manually enrolled AND the user has admin rights, activation lock would be reactivated once that MDM Profile is removed (either on the next reboot, or if the user toggles Find My off and on again).
  * Alternatively, if you have configured your MDM to allow user-based Activation Lock, then activation lock will become active again once they turn Find My Mac back on.
* **Why didn't you just use `nvram fmm-mobileme-token-FMM` to determine Activation Lock status?**
  * That reports on whether FindMy is enabled, regardless of actual Activation Lock status.
* **The script says the device is still activation locked but can't find any users with Find My enabled.**
  * There are edge cases where this can occur. In instances where an activation lock is enabled and a user DOES have Find My enabled, it typically resolves itself eventually. There are rare instances where a user doesn't have a FindMy status written to their `MobileMeAccounts.plist` when the script runs.
  * Another scenario: the user logs out of iCloud but the activation lock isn't successfully removed. You can end up with a device where activation lock is enabled but no currently logged in user has Find My enabled. You can work around this by logging into another iCloud account and logging back out.
  * Keep in mind that the source of truth for Activation Lock status lives on Apple's servers. This script leverages a cached version of that status locally, and there are edge cases where the cached status can be incorrect.

## Credits
Originally created by [Brian Van Peski](https://www.macosadventures.com) — macOS Adventures.
V2.0 rewritten and maintained by [Branch Digital](https://branch.digital).
