# remotes-asennus

Etälaitteiden käyttöönottoskripti. Tässä repossa ei ole salaisuuksia selväkielisenä: `paketti.enc` on
salattu asennusavaimella, ja varsinaiset asetukset ovat yksityisessä repossa.

Linux Mint / Ubuntu:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/lasseolli/remotes-asennus/main/asenna.sh)" -- <ryhmä>
```

Windows 10/11 (järjestelmänvalvojan PowerShell):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/lasseolli/remotes-asennus/main/asenna.ps1))) <ryhmä>
```
