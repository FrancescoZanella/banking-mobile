# Regole R8 per la build di release (codice nativo e riflessione dei plugin).

# SQLCipher: classi chiamate dal codice nativo (JNI).
-keep class net.zetetic.** { *; }
-keep class net.sqlcipher.** { *; }

# flutter_local_notifications: dati delle notifiche serializzati con Gson.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keep class * extends com.google.gson.TypeAdapter
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Componenti differiti di Flutter (Play Core): non usati da questa app.
-dontwarn com.google.android.play.core.**
