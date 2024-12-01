# ibm-x3650-m4-silent-mode
A custom script that turn my Homelab's IBM x3650 m4 silent (Because I sleep near it)

## Installation 

You can run the following steps to install the script and made it run at startup : 

```
# Download the script
sudo curl -fsSLo /usr/local/bin/silent_mode_script.sh https://raw.githubusercontent.com/harryludemann/ibm-x3650-m4-silent-mode/main/silent_mode_script.sh

# Mark Executable
sudo chmod +x /usr/local/bin/silent_mode_script.sh

# Download the service definition
sudo curl -fsSLo /etc/systemd/system/silent_mode_script.service https://raw.githubusercontent.com/harryludemann/ibm-x3650-m4-silent-mode/main/silent_mode_script.service

# Make ipmitool password-less sudo by adding the line to visudo
sudo visudo
root ALL=(ALL) NOPASSWD: /usr/bin/ipmitool

# Reload systemctl scripts
sudo systemctl daemon-reload

# Register and start the service
sudo systemctl enable --now silent_mode_script
```

Everything must work well now.

## Customize the curve

You can edit the script located `/usr/local/bin/silent_mode_script.sh` to change the temp values to tweak at your need.

Important value you can change is : 
- `min_temp=40`
- `max_temp=80`
and the `fan_speed` function in the `else` block to match your custom curve.

## Any impact in the perfs ?

No it shouldn't take much resources on your server : 

https://github.com/shiipou/ibm-x3650-m4-silent-mode/assets/38187238/503beb20-0d7c-4e77-8761-82d2327bd782

