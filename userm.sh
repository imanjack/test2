#!/bin/bash

HUB_NAME="MYHUB"
ADMIN_PASSWORD="REPLACE_WITH_YOUR_ADMIN_PASSWORD"
VPNCMD="/usr/local/vpnserver/vpncmd localhost /SERVER /PASSWORD:$ADMIN_PASSWORD /HUB:$HUB_NAME"

add_user() {
  read -p "Enter new username: " username
  read -s -p "Enter password for $username: " password
  echo
  $VPNCMD /CMD UserCreate $username
  $VPNCMD /CMD UserPasswordSet $username /PASSWORD:$password
  echo "✅ User $username created."
}

remove_user() {
  read -p "Enter username to delete: " username
  $VPNCMD /CMD UserDelete $username
  echo "❌ User $username deleted."
}

change_password() {
  read -p "Enter username: " username
  read -s -p "Enter new password: " password
  echo
  $VPNCMD /CMD UserPasswordSet $username /PASSWORD:$password
  echo "🔑 Password updated for $username."
}

echo "SoftEther VPN User Manager"
echo "1) Add User"
echo "2) Remove User"
echo "3) Change Password"
read -p "Choose an option: " choice

case $choice in
  1) add_user ;;
  2) remove_user ;;
  3) change_password ;;
  *) echo "Invalid option" ;;
esac
