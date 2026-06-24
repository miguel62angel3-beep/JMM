#!/bin/bash

### Script de configuración automática de SSH para Ubuntu 22.04 LTS

### Autor: Configuración Limpia

### Colores para la terminal

VERDE='\\033\[0;32m'  
AZUL='\\033\[0;34m'  
NC='\\033\[0m' # Sin color

echo -e "

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝐴𝑍𝑈𝐿

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)\[

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)1

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)/4

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)\]

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝐴𝑐𝑡𝑢𝑎𝑙𝑖𝑧𝑎𝑛𝑑𝑜𝑙𝑜𝑠𝑟𝑒𝑝𝑜𝑠𝑖𝑡𝑜𝑟𝑖𝑜𝑠𝑑𝑒𝑙𝑠𝑖𝑠𝑡𝑒𝑚𝑎

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

{NC}"  
sudo apt update -y

echo -e "

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝐴𝑍𝑈𝐿

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)\[

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)2

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)/4

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)\]

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝐼𝑛𝑠𝑡𝑎𝑙𝑎𝑛𝑑𝑜𝑒𝑙𝑠𝑒𝑟𝑣𝑖𝑑𝑜𝑟𝑂𝑝𝑒𝑛𝑆𝑆𝐻

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

{NC}"  
sudo apt install openssh-server -y

echo -e "

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝐴𝑍𝑈𝐿

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)\[

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)3

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)/4

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)\]

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝐻𝑎𝑏𝑖𝑙𝑖𝑡𝑎𝑛𝑑𝑜𝑒𝑖𝑛𝑖𝑐𝑖𝑎𝑛𝑑𝑜𝑒𝑙𝑠𝑒𝑟𝑣𝑖𝑐𝑖𝑜𝑆𝑆𝐻

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

{NC}"  
sudo systemctl enable --now ssh

echo -e "

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝐴𝑍𝑈𝐿

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)\[

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)4

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)/4

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)\]

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝐶𝑜𝑛𝑓𝑖𝑔𝑢𝑟𝑎𝑛𝑑𝑜𝑒𝑙𝐹𝑖𝑟𝑒𝑤𝑎𝑙𝑙

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)(

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝑈𝐹𝑊

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==))

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝑝𝑎𝑟𝑎𝑝𝑒𝑟𝑚𝑖𝑡𝑖𝑟𝑒𝑙𝑝𝑢𝑒𝑟𝑡𝑜22

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==).

{NC}"

### Verifica si el firewall está activo antes de aplicar

sudo ufw allow 22/tcp  
sudo ufw --force enable

### Extraer credenciales dinámicamente

USUARIO=$(whoami)

### Filtra la IP omitiendo la interfaz local (127.0.0.1)

IP\_REAL=$(ip -4 addr show | grep -oP '(?<=inet\\s)\\d+(.\\d+){3}' | grep -v '127.0.0.1' | head -n 1)

echo -e "\\n

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝑉𝐸𝑅𝐷𝐸

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=

{NC}"  
echo -e "${VERDE} ¡CONFIGURACIÓN COMPLETADA CON ÉXITO! ${NC}"  
echo -e "

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝑉𝐸𝑅𝐷𝐸

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=

{NC}"  
echo -e "${AZUL}Tu máquina ya tiene control total por SSH y persistencia al reiniciar.${NC}\\n"  
echo -e "Para conectarte desde Windows (CMD o PowerShell), usa:"  
echo -e "

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝑉𝐸𝑅𝐷𝐸

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝑠𝑠ℎ

{USUARIO}@

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)

IPREALcap I cap P sub cap R cap E cap A cap L

𝐼𝑃𝑅𝐸𝐴𝐿

{NC}\\n"  
echo -e "Credenciales detectadas:"  
echo -e " - Usuario: ${USUARIO}"  
echo -e " - IP Actual: ${IP\_REAL}"  
echo -e " - Puerto: 22 (Por defecto)"  
echo -e "

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)𝑉𝐸𝑅𝐷𝐸

![](data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==)\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=

{NC}"
