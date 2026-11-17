# HomeHub iOS (SwiftUI) — JellyControl + Deal Radar

100 % native SwiftUI iOS-App (optimiert für **iPhone 17 Pro**, iOS 17–26+), die deine beiden Raspberry-Pi-Dienste in einer App vereint:
* **⚡ JellyControl:** Live-Status, Apple Charts Watt-Sparkline, CPU/GPU/RAM-Telemetrie, Wake-on-LAN, Jellyfin-Direktstart, HomeServer ↔ Gaming Switch, DarkRoom RGB, Ruhezustand (0W) & alle 10 Dienste.
* **🏷️ Deal Radar:** Alle Kleinanzeigen-Deals mit Score & Preisdrop-Tracking, Favoriten/Kontaktiert/Archiv/Notizen, Schnellscan & **Tiefenscan (alle Seiten)**, **Neues Gerät hinzufügen** (ohne URL-Gefummel) und **Preisspannen-Verwaltung & Löschen**.
* **🔌 System & Sicherheit:** Automatisches Tailscale ↔ WLAN Routing (`100.100.2.103` ↔ `192.168.0.87`), Pi-4-Telemetrie, **Face ID-geschützter Notfall Power-Cycle** und Live-Status deines eigenen Pi Anisette-v3-Servers.

---

## 🚀 Fertige `HomeHub.ipa` bauen (2 einfache Wege)

### Weg A: Kostenlos & automatisch über GitHub Actions (ohne Mac!)
1. Erstelle auf GitHub ein neues (auch **privates**) Repository, z. B. `HomeHub-iOS`.
2. Öffne PowerShell in diesem Ordner (`C:\Users\magnu\Desktop\HomeHub-iOS`) und pushe das Projekt:
   ```powershell
   git init
   git add .
   git commit -m "Initial HomeHub iOS App"
   git branch -M main
   git remote add origin https://github.com/<DEIN-USER>/HomeHub-iOS.git
   git push -u origin main
   ```
3. GitHub Actions startet automatisch den macOS-Build (`.github/workflows/build-ipa.yml`, dauert ca. 2 Minuten).
4. Lade unter **Actions → Build HomeHub iOS IPA** (oder direkt unter **Releases**) die fertige **`HomeHub.ipa`** herunter!

### Weg B: Direkt lokal auf deinem MacBook
Kopiere den Ordner auf dein MacBook und starte im Terminal:
```bash
chmod +x build-mac.sh
./build-mac.sh
```
Danach liegt die fertige `HomeHub.ipa` direkt im Projektordner.

---

## 📱 Sideloading & Automatisches 7-Tage-Signing mit deinem Raspberry Pi

### 1. SideStore + StosVPN (einmalig)
* Installiere **SideStore** über dein vorhandenes `iloader` auf dem iPhone 17 Pro und **StosVPN** aus dem App Store.
* Öffne **SideStore → Einstellungen → Anisette Server** und trage deinen eigenen 24/7 Raspberry-Pi-Server ein:
  * Im Heim-WLAN: `http://192.168.0.87:6969`
  * *(Hinweis: Da iOS nur ein VPN gleichzeitig erlaubt, ist bei aktivem StosVPN im Heim-WLAN `192.168.0.87:6969` direkt lokal erreichbar!)*
* Installiere **`HomeHub.ipa`** direkt in SideStore (über `+` → `HomeHub.ipa` auswählen).

### 2. Vollautomatisches Re-Signing im Schlaf (iOS Kurzbefehl)
Erstelle in der Apple **Kurzbefehle-App → Automation → + → Tageszeit** (z. B. täglich **04:00 Uhr**, „Sofort ausführen“):
1. *(Optional)* **Wenn Batterie geladen wird**
2. **StosVPN verbinden** (Aktion von StosVPN)
3. **2 Sekunden warten**
4. **SideStore → Alle Apps aktualisieren (Refresh All Apps)**
5. **StosVPN trennen** → **Tailscale verbinden** (so bist du morgens direkt wieder im Tailnet!)

Damit verlängert dein iPhone die Signatur von **HomeHub** & **SideStore** alle paar Tage vollautomatisch – komplett ohne PC!
