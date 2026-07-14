# kotlinx.serialization: keep serializers for our models
-keepclassmembers class com.evanjt.traintime.** {
    *** Companion;
}
-keepclasseswithmembers class com.evanjt.traintime.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Garmin Connect IQ Mobile SDK. The Connect Mobile app broadcasts Parcelable
# extras (IQDevice, IQApp, IQMessage, …) that our process unmarshals by their
# original class name. R8 must not rename or strip these classes, or the read
# side fails Class.forName with ClassNotFoundException and the SDK's broadcast
# receiver crashes the app on launch (BadParcelableException).
-keep class com.garmin.android.connectiq.** { *; }
