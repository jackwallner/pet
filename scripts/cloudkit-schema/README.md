# CloudKit setup

Native Mac tool built from the real `Shared/Models/PetModel.swift`. It uses temporary local stores and never opens the app's database.

```sh
xcodegen generate --spec scripts/cloudkit-schema/project.yml
xcodebuild -project scripts/cloudkit-schema/PetCloudSchema.xcodeproj -scheme PetCloudSchema -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/NativeCloudSchema -allowProvisioningUpdates build
```

Launch with `open`, not the executable path: `open -W --stdout out.txt --stderr err.txt build/NativeCloudSchema/Build/Products/Debug/PetCloudSchema.app --args <flag>`.

- No flag: validates the model with Apple's schema dry run.
- `--initialize-development`: creates the Development schema.
- `--verify-share`: makes a real `CKShare` on a temporary household, checks the link, then purges it.

Order: initialize Development, run `--verify-share` on Development (this creates the `cloudkit.share` type, which initialization never does), deploy Development to Production in the CloudKit Console, then run the Release build's `--verify-share` against Production. Any model change repeats this before the build that ships it.
