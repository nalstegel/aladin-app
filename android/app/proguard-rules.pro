# Pravila za R8 v release izdaji.
#
# Flutter sam poskrbi za svoje razrede, tu so samo vtičniki, ki uporabljajo
# refleksijo in bi jim R8 sicer odstranil razrede, ki jih potrebujejo.

# --- Firebase / Firestore ---
# Modeli se berejo prek refleksije, zato jim ohranimo imena polj.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- mobile_scanner (MLKit) ---
# Skeniranje QR etiket je jedro aplikacije; brez tega tiho neha delovati.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.odml.** { *; }
-dontwarn com.google.mlkit.**

# MLKit prek refleksije nalaga tudi modele za druge formate, ki jih ne
# uporabljamo — brez tega R8 javi manjkajoče razrede.
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode.**

# --- Anotacije, ki jih vlečejo Firebase odvisnosti ---
-dontwarn org.checkerframework.**
-dontwarn javax.annotation.**
-dontwarn com.google.errorprone.annotations.**
