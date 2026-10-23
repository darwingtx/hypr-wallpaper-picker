-- Atajos de hypr-wallpaper-picker (los añade install.sh a tu keybinds.lua)

-- Wallpapers online (wallhaven / bing) con regeneracion del tema Material You
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("$HOME/.config/hypr/custom/scripts/wallpaper_menu.sh"), { description = "Wallpaper: elegir fondo online" })

-- Galeria con previews: miniaturas ligeras y solo se descarga la que eliges
hl.bind("SUPER + SHIFT + G", hl.dsp.exec_cmd("$HOME/.config/hypr/custom/scripts/wallpaper_gallery.py"), { description = "Wallpaper: galeria con previews" })
