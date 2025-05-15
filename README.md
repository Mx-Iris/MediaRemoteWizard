# MediaRemoteWizard

This tool allows any application running on macOS 15.4 to access MediaRemote to obtain NowPlaying information.

After macOS 15.4, Apple added entitlement verification in the mediaremoted daemon. Clients without the corresponding entitlement will be denied access to NowPlaying information, causing applications that previously relied on this private framework to stop working, including LyricsX which I maintain.

This application injects code into mediaremoted, swapping core methods to return YES, thus allowing any client to connect.

Since code injection is required, you must disable SIP (System Integrity Protection) to use MediaRemoteWizard.

Apple Silicon must also enable `arm64e_preview_abi` because Apple does not allow third-party arm64e architecture apps to run by default.

```
sudo nvram boot-args=-arm64e_preview_abi
```

## Usage

After opening the application installation helper, try to keep the app running in the background to prevent mediaremoted from restarting and causing the injection to invalid.

## Security Concerns

Using this software reduces the security of your system. In future updates, we may add a whitelist feature to allow users to specify which applications can access MediaRemote, while maintaining Apple's original logic for all other applications.

## Disclaimer

**USE AT YOUR OWN RISK**: The developer assumes no responsibility or liability for any consequences resulting from the use of this software. By using MediaRemoteWizard, you acknowledge that you understand the potential risks involved, including but not limited to system instability, security vulnerabilities, or other unforeseen issues. This tool modifies system behavior and should be used with caution.
