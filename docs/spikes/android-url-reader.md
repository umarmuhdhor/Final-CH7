# Spike: read the Chrome URL on Android

**Question:** Can a separate Android app see the page open in Chrome, with Chrome unchanged, well enough to run the detector?
**Fallback:** link interceptor (Shoo as default browser, forwards to Chrome). Sees full URLs, but only for links opened from other apps.

Spike code: [android-url-reader/](android-url-reader/). Plain Java and SDK tools only, throwaway. No PRD ID yet.

## How to run
Needs `ANDROID_HOME` and a device or emulator with Chrome.

```bash
docs/spikes/android-url-reader/build.sh
```

```bash
docs/spikes/android-url-reader/run-test.sh
```

`run-test.sh` turns the service on through `adb`. Turn it off afterwards in Settings > Accessibility.
The log holds full URLs and stays on the device. Page text is counted, never logged.

## To test
- [ ] Does the `url_bar` node hold path, query and scheme, or only the domain?
- [ ] Does the web content expose the full URL (`rootWebAreaUrl`)? This would replace the address bar, and is a private Chrome detail.
- [ ] A redirect: do we see the final URL?
- [ ] Typing in the address bar is ignored (no BAR line until the page opens)?
- [ ] Overlay shows on top of Chrome with no extra permission?
- [ ] How much page text and how many links are readable (layer 3–4)?
- [ ] Time from accessibility event to reading the URL, and time to walk the tree?
- [ ] Link from WhatsApp or SMS: Custom Tab or Chrome tab? Does `url_bar` exist there?
- [ ] Incognito tab.
- [ ] Sideloaded APK on Android 13+: is enabling blocked by restricted settings?

## Result
- Decision: 
- Tested on: 
- URL detail: 
- Page content: 
- Latency: 
