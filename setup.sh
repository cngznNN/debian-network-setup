#!/bin/bash
#
# Debian/Ubuntu Server Ağ Otomatik Yapılandırma
# Kullanım: curl -sSL https://raw.githubusercontent.com/KULLANICI_ADIN/network-setup/main/setup.sh | sudo bash
#
# Root yetkisi kontrolü
if [ "$EUID" -ne 0 ]; then 
    echo "Bu scripti root olarak çalıştırmalısınız: sudo bash $0"
    exit 1
fi

echo "=== Debian Ağ Yapılandırma Scripti ==="
echo

# Mevcut IP'yi al
CURRENT_IP=$(hostname -I | awk '{print $1}')
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ -z "$CURRENT_IP" ]; then
    echo "Hata: Şu anda bir IP adresi alınamadı."
    echo "Önce DHCP ile bağlantı sağlayın."
    exit 1
fi

echo "Mevcut Ağ Bilgileri:"
echo "  Arayüz: $INTERFACE"
echo "  Mevcut IP: $CURRENT_IP"
echo "  Gateway: $(ip route | grep default | awk '{print $3}')"
echo "  DNS: $(grep nameserver /etc/resolv.conf | awk '{print $2}' | head -n1)"
echo

# Kullanıcıya seçenek sun
echo "Ne yapmak istersiniz?"
echo "1) Mevcut DHCP IP'sini sabit IP yap (önerilen - kolay)"
echo "2) Manuel IP gir"
read -p "Seçiminiz (1 veya 2): " choice

case $choice in
    1)
        STATIC_IP=$CURRENT_IP
        GATEWAY=$(ip route | grep default | awk '{print $3}')
        DNS=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | head -n1)
        ;;
    2)
        read -p "Sabit IP adresi (örn: 192.168.1.100): " STATIC_IP
        read -p "Gateway (örn: 192.168.1.1): " GATEWAY
        read -p "DNS sunucu (örn: 8.8.8.8): " DNS
        ;;
    *)
        echo "Geçersiz seçim!"
        exit 1
        ;;
esac

# Netmask hesapla (çoğu ev ağı için /24)
NETMASK="255.255.255.0"

echo
echo "Uygulanacak Yapılandırma:"
echo "  IP: $STATIC_IP"
echo "  Gateway: $GATEWAY"
echo "  DNS: $DNS"
echo "  Netmask: $NETMASK"
echo

read -p "Devam edilsin mi? (e/h): " confirm
if [ "$confirm" != "e" ]; then
    echo "İptal edildi."
    exit 0
fi

# Yedek al
echo "Mevcut yapılandırma yedekleniyor..."
cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S)

# Yeni yapılandırma dosyasını oluştur
echo "Yeni yapılandırma yazılıyor..."
cat > /etc/network/interfaces << EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# Loopback interface
auto lo
iface lo inet loopback

# Primary network interface
auto $INTERFACE
iface $INTERFACE inet static
    address $STATIC_IP
    netmask $NETMASK
    gateway $GATEWAY
    dns-nameservers $DNS
EOF

# DNS yapılandırması
echo "DNS yapılandırması güncelleniyor..."
cat > /etc/resolv.conf << EOF
nameserver $DNS
nameserver 8.8.8.8
EOF

# resolv.conf'un üzerine yazılmaması için
chattr +i /etc/resolv.conf 2>/dev/null || true

echo
echo "✓ Yapılandırma tamamlandı!"
echo
echo "Ağ servisini yeniden başlatmak için:"
echo "  systemctl restart networking"
echo
echo "Veya sistemi yeniden başlatın:"
echo "  reboot"
echo
read -p "Şimdi ağ servisini yeniden başlatalım mı? (e/h): " restart
if [ "$restart" = "e" ]; then
    echo "Ağ servisi yeniden başlatılıyor..."
    systemctl restart networking
    sleep 2
    echo
    echo "Yeni IP durumu:"
    ip addr show $INTERFACE | grep "inet "
    echo
    echo "Bağlantı testi yapılıyor..."
    if ping -c 2 8.8.8.8 > /dev/null 2>&1; then
        echo "✓ İnternet bağlantısı çalışıyor!"
    else
        echo "⚠ İnternet bağlantısı kurulamadı. Yapılandırmayı kontrol edin."
    fi
fi

echo
echo "Eski yapılandırma /etc/network/interfaces.backup* olarak yedeklendi."
echo "Sorun olursa: mv /etc/network/interfaces.backup* /etc/network/interfaces"
