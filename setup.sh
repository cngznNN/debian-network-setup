#!/bin/bash
#
# Debian/Ubuntu Server Ağ Otomatik Yapılandırma
# 
# Kullanım 1 (otomatik - mevcut IP'yi sabit yap):
#   curl -sSL https://raw.githubusercontent.com/cngznNN/debian-network-setup/main/setup.sh | sudo bash -s auto
#
# Kullanım 2 (interaktif):
#   curl -sSL https://raw.githubusercontent.com/cngznNN/debian-network-setup/main/setup.sh | sudo bash -s interactive
#
# Kullanım 3 (manuel IP):
#   curl -sSL https://raw.githubusercontent.com/cngznNN/debian-network-setup/main/setup.sh | sudo bash -s manual 192.168.1.100 192.168.1.1 8.8.8.8
#

# Root yetkisi kontrolü
if [ "$EUID" -ne 0 ]; then 
    echo "Bu scripti root olarak çalıştırmalısınız: sudo bash $0"
    exit 1
fi

MODE="${1:-interactive}"

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

# Mod seçimi
case $MODE in
    auto)
        echo "MOD: Otomatik - Mevcut DHCP IP'si sabitlenecek"
        STATIC_IP=$CURRENT_IP
        GATEWAY=$(ip route | grep default | awk '{print $3}')
        DNS=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | head -n1)
        ;;
    manual)
        echo "MOD: Manuel IP"
        STATIC_IP="${2:-$CURRENT_IP}"
        GATEWAY="${3:-$(ip route | grep default | awk '{print $3}')}"
        DNS="${4:-8.8.8.8}"
        ;;
    interactive)
        echo "MOD: İnteraktif"
        echo "Ne yapmak istersiniz?"
        echo "1) Mevcut DHCP IP'sini sabit IP yap (önerilen - kolay)"
        echo "2) Manuel IP gir"
        
        # Terminal'den direkt oku
        exec < /dev/tty
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
        ;;
    *)
        echo "Hata: Geçersiz mod!"
        echo ""
        echo "Kullanım örnekleri:"
        echo "  sudo bash $0 auto                                    # Otomatik (mevcut IP'yi sabit yap)"
        echo "  sudo bash $0 interactive                             # İnteraktif mod"
        echo "  sudo bash $0 manual 192.168.1.100 192.168.1.1 8.8.8.8  # Manuel IP"
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

if [ "$MODE" = "interactive" ]; then
    read -p "Devam edilsin mi? (e/h): " confirm
    if [ "$confirm" != "e" ]; then
        echo "İptal edildi."
        exit 0
    fi
else
    echo "5 saniye içinde devam edilecek... (Ctrl+C ile iptal)"
    sleep 5
fi

# Yedek al
echo "Mevcut yapılandırma yedekleniyor..."
cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

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

# Ağ servisini yeniden başlat
echo "Ağ servisi yeniden başlatılıyor..."
systemctl restart networking 2>/dev/null || /etc/init.d/networking restart
sleep 2

echo
echo "Yeni IP durumu:"
ip addr show $INTERFACE | grep "inet " || echo "IP bilgisi alınamadı"

echo
echo "Bağlantı testi yapılıyor..."
if ping -c 2 8.8.8.8 > /dev/null 2>&1; then
    echo "✓ İnternet bağlantısı çalışıyor!"
else
    echo "⚠ İnternet bağlantısı kurulamadı. Yapılandırmayı kontrol edin."
    echo "Eski yapılandırmaya dönmek için:"
    echo "  ls -la /etc/network/interfaces.backup*"
    echo "  mv /etc/network/interfaces.backup.XXXX /etc/network/interfaces"
    echo "  systemctl restart networking"
fi

echo
echo "Tamamlandı! SSH bağlantısı kesilirse yeni IP ile bağlanın: $STATIC_IP"
