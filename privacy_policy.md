# Privacy Policy

**Last Updated: January 19, 2026**

This privacy policy applies to the Attention Arsenal app (hereby referred to as "Application") for mobile devices that was created by Danaid Sinani (hereby referred to as "Service Provider") as an Open Source service. This service is intended for use "AS IS".

## Information Collection and Use

### What information does the Application obtain and how is it used?

**User-Generated Content:**

- The Application stores reminders, tasks, and notes (collectively "Arsenals") that you create
- This includes arsenal titles, descriptions, notification intervals (minutes, hours, daily, weekly, monthly), selected days of the week, days of the month, and notification times
- This content is stored **locally on your device** using Core Data
- No account registration is required
- Your data is never uploaded to our servers

**Calendar Information:**

- If you grant permission, the Application can read your calendar events
- Calendar data is only used to display events within the app and suggest reminders
- Calendar information is **not stored permanently** and is **not sent to external servers**
- You can revoke calendar access at any time in iOS Settings

**Email Information (Gmail/Outlook):**

- If you choose to connect your email account, the Application can read your recent emails
- The Application uses Google Sign-In (for Gmail) or Microsoft Authentication (for Outlook) to securely access your emails
- Email data accessed includes: sender name, subject line, date, read status, and a preview of the email body
- Email content is displayed within the app so you can create reminders for emails that need follow-up
- When you tap "Add" on an email, the email's subject, sender, and preview are sent to OpenAI to generate a reminder suggestion
- Email data is **not stored permanently** on our servers
- You can disconnect your email account at any time within the app
- Revoking access removes the app's ability to read your emails

**Voice Commands (Siri):**

- If you use Siri shortcuts, your voice input is processed by Apple's Siri service
- Voice commands are converted to text and sent to OpenAI's API for natural language processing
- We do not store or have access to your voice recordings

**Home Screen Widgets:**

- The Application offers optional home screen widgets that display your arsenals
- Widget data is stored locally on your device using App Groups (shared storage between the app and widget)
- Widgets display your arsenal titles, descriptions, and notification intervals on your home screen
- **Privacy Note**: Widget content is visible to anyone who can see your device's home screen
- All widget data remains on your device and is never transmitted to external servers
- You can remove widgets at any time by removing them from your home screen

### Third-Party Services

**OpenAI API Integration:**

The Application uses OpenAI's API to provide intelligent features including:

- Parsing natural language voice commands
- Generating reminder suggestions from calendar events
- Generating reminder suggestions from emails
- Creating smart descriptions and notification intervals

**What data is sent to OpenAI:**

- Text of your voice commands (when using Siri)
- Calendar event titles, dates, and descriptions (when creating reminders from events)
- Email sender, subject, and preview text (when creating reminders from emails)
- No personally identifiable information beyond what's in your calendar events or emails
- No permanent identifiers

**OpenAI's Data Usage:**

- Data sent to OpenAI is subject to [OpenAI's Privacy Policy](https://openai.com/privacy)
- OpenAI may use data to improve their services
- OpenAI retains data according to their retention policies
- Your API requests are not associated with your personal identity

**Your Control:**

- You can choose not to use AI-powered features
- Manually created reminders do not use OpenAI
- Only specific features (Siri commands, "Add" button on events/emails) send data to OpenAI

### Local Storage

**On-Device Data:**

- All reminders and tasks are stored locally using Core Data
- Data remains on your device and in your iCloud (if iOS backup is enabled)
- We cannot access your local data
- Uninstalling the app deletes all local data

**Statistics & Streaks:**

- Your completion statistics (total completed, streaks) are stored **locally on your device** using UserDefaults
- Statistics include: total arsenals completed, completion dates, streak counts
- Statistics are backed up to Apple's iCloud Key-Value Storage periodically for recovery purposes (e.g., if you reinstall the app or switch devices)
- No personally identifiable information is stored
- This backup data is stored in your personal iCloud account and is not accessible to us

**Your OpenAI API Key:**

- If you configure your own OpenAI API key, it is stored securely on your device
- The API key is never transmitted to us
- You are responsible for keeping your API key secure

### Notifications

- The Application uses local notifications to remind you about tasks
- Notifications are generated locally on your device
- No data is sent to external servers for notifications
- You can disable notifications at any time in iOS Settings

## Does the Application collect precise real-time location information?

No, this Application does not collect, access, or track any location information from your mobile device.

## Data Sharing

**We do not:**

- Collect any analytics or crash reports
- Share your data with advertisers
- Sell your information to third parties
- Track your usage patterns

**Third-party data sharing:**

- Only OpenAI receives data when you use AI-powered features
- Apple processes Siri voice commands according to their privacy policy
- Your calendar provider (Apple, Google, etc.) provides calendar data according to their privacy policy
- Google processes Gmail authentication according to their privacy policy (if you connect Gmail)
- Microsoft processes Outlook authentication according to their privacy policy (if you connect Outlook)

## Your Rights and Choices

**You can:**

- Delete all your data by uninstalling the app
- Revoke calendar permissions in iOS Settings → Privacy & Security → Calendars
- Disconnect your Gmail or Outlook account within the app at any time
- Disable Siri integration in iOS Settings → Siri & Search
- Turn off notifications in iOS Settings → Notifications
- Stop using AI features to prevent data being sent to OpenAI

**Data Retention:**

- Local data: Until you delete the app
- OpenAI: According to their retention policy (typically 30 days)
- Calendar access: No data is retained after you revoke permission
- Email access: No data is retained after you disconnect your account

## Children's Privacy

The Application is not directed to children under the age of 13. We do not knowingly collect personally identifiable information from children under 13.

If you are a parent or guardian and believe your child has provided information to our Application, please contact us at danaid@bu.edu so we can delete such information.

You must be at least 16 years of age to consent to the processing of your information in your country (in some countries we may allow your parent or guardian to do so on your behalf).

## Security

We are committed to protecting your information:

**Local Security:**

- Data is stored using iOS secure storage mechanisms
- API keys are stored in iOS Keychain or UserDefaults
- All data inherits iOS security protections (encryption at rest, Face ID/Touch ID)

**Network Security:**

- Communications with OpenAI use HTTPS encryption
- No unencrypted data transmission

**Limitations:**

- We cannot guarantee absolute security
- You are responsible for securing your device
- If you use your own OpenAI API key, you are responsible for its security

## International Users

OpenAI's services are based in the United States. By using AI-powered features, you consent to the transfer of your data to the United States for processing.

## Changes to This Privacy Policy

This Privacy Policy may be updated from time to time. We will notify you of any changes by:

- Updating the "Last Updated" date at the top
- Releasing an app update with the new policy

Continued use of the Application after changes constitutes acceptance of the updated policy.

## Data Protection Rights (GDPR/CCPA)

If you are in the EU or California, you have certain data protection rights:

**Right to Access:** Request copies of your data (stored locally on your device)
**Right to Rectification:** Correct inaccurate data (edit in the app)
**Right to Erasure:** Delete your data (uninstall the app)
**Right to Restrict Processing:** Stop using AI features
**Right to Data Portability:** Export your data (available in app settings)
**Right to Object:** Opt-out of AI processing (don't use those features)

To exercise these rights for data sent to OpenAI, please contact OpenAI directly.

## California Privacy Rights

California residents have the right to request:

- What personal information we collect (see above)
- How we use personal information (see above)
- Whether we sell personal information (we don't)
- Request deletion of personal information (uninstall the app)

## Your Consent

By using the Application, you consent to:

- Local storage of your reminders and tasks
- Processing of your data as described in this policy
- Data being sent to OpenAI when using AI-powered features
- Apple processing Siri commands according to their policy
- Google/Microsoft processing authentication when you connect Gmail/Outlook

You can withdraw consent at any time by:

- Uninstalling the application
- Disabling specific permissions in iOS Settings
- Disconnecting your email account within the app
- Not using AI-powered features

## Third-Party Links and Services

This Privacy Policy applies only to Attention Arsenal. When you use features that involve third-party services:

- **OpenAI:** [OpenAI Privacy Policy](https://openai.com/privacy)
- **Apple Siri:** [Apple Privacy Policy](https://www.apple.com/privacy/)
- **Google (Gmail):** [Google Privacy Policy](https://policies.google.com/privacy)
- **Microsoft (Outlook):** [Microsoft Privacy Statement](https://privacy.microsoft.com/en-us/privacystatement)
- **Calendar Providers:** Check your calendar provider's privacy policy

## Contact Us

If you have any questions about this Privacy Policy or the Application's practices, please contact:

**Email:** danaid@bu.edu

For questions about data sent to OpenAI, contact OpenAI at: privacy@openai.com

## Open Source

This Application is open source. You can review the code to verify our privacy practices at: [GitHub Repository URL]

---

_This privacy policy is effective as of January 19, 2026_

_Generated with [App Privacy Policy Generator](https://app-privacy-policy-generator.nisrulz.com/) and customized for Attention Arsenal_
