# Règles R8 de l'APK de publication.

# WorkManager (VerificationMiseAJour.kt) range ses tâches dans une base Room, que Room crée par
# réflexion à partir de la classe générée WorkDatabase_Impl. Sans ces règles, R8 retire son
# constructeur et l'application plante dès le démarrage, avant tout écran (version 1.1.3) :
# NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init>
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
