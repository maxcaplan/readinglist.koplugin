# readinglist.koplugin
A plugin for [KOReader](https://github.com/koreader/koreader "KOReader") to create and manage reading lists directly in your reader.

<details>
  <summary><h2>Table of Contents</h2></summary>
  <ol>
    <li><a href="#features">Features</a></li>
    <li>
      <a href="#installation">Installation</a>
      <ul>
        <li><a href="#uninstall">Uninstall</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
  </ol>
</details>

## Features
- Easily accessible from the tools menu
- Create any number of lists
- Mark list items as "read" with checkbox button
- Lists stored in easily editable XML file

## Installation
readinglist.koplugin has only been tested on a Kobo Libra 2.

### Prerequisites

- **[KOReader v2025.10](https://github.com/koreader/koreader "KOReader")**
readinglist.koplugin has only been tested on v2025.10 of KOReader.
Follow the [KOReader installation](https://github.com/koreader/koreader/wiki "KOReader installation") guide for your device.

### Step 1: Download the plugin
- On your computer, download the zip archive for the latest release of readinglist.koplugin from the repository [releases pages](https://github.com/maxcaplan/readinglist.koplugin/releases "releases pages").

### Step 2: Locate the KOReader installation folder
- Connect to your device via USB.
- Depending on your device, the location of your KOReader installation folder will vary as follows:
	- On Kobo: `/.adds/koreader/`
	- On Kindle: `/koreader`
	- On Android: koreader at the root of your onboard storage
	- On Pocketbook: `/applications/koreader`
	- On Cervantes: `/mnt/private/koreader`
- Following this step, `[koreader]/` is a placeholder for the KOReader installation folder on your device.

### Step 3:  Install the plugin
- On your computer, extract the `readinglist.koplugin` folder from the plugin release zip archive `readinglist-[VERSION].zip`.
- Copy the extracted `readinglist.koplugin` folder from your computer to `[koreader]/plugins/` on your device
- Safely eject your device from your computer.
- Launch or restart KOReader on your device. The plugin should now be installed.

### Step 4: Enable the plugin
- Open the KOReader top menu on your device.
- Open the tools menu (wrench and screwdriver icon).
- Navigate to `More tools > Plugin management`.
- Ensure the checkbox next to `Reading list` is checked.
- readinglist.koplugin should now be enabled.

### Uninstall
To uninstall the plugin, simply delete the `readinglist.koplugin` folder on your device at `[koreader]/plugins/`. Once KOReader is restarted, the plugin will be uninstalled.

## Usage
 - **TODO:** Add usage readme section

## Roadmap
- [ ] Ability to set custom storage location for plugin XML
- [ ] Ability to link list items to books to open when pressed.
- [ ] Ability to link list items to entries of a books table of contents.
- [ ] Ability to add text blocks to lists.
- [ ] Ability to archive reading lists
- [ ] Bulk operations for reading lists and list items
- [ ] Web based tool for creating and editing plugin XML

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License
[AGPL-3.0 © Max Caplan](https://github.com/maxcaplan/readinglist.koplugin/blob/master/LICENSE)
