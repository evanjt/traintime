# kotlinx.serialization: keep serializers for our models
-keepclassmembers class com.evanjt.traintime.** {
    *** Companion;
}
-keepclasseswithmembers class com.evanjt.traintime.** {
    kotlinx.serialization.KSerializer serializer(...);
}
