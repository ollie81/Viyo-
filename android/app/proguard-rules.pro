# flutter_stripe pulls in react-native-stripe-sdk's push-provisioning
# module (adding a card to Google Wallet), which references classes
# from an optional Stripe artifact this app doesn't depend on since it
# doesn't use that feature — R8 just needs to be told these are safe
# to leave unresolved rather than failing the build over them.
-dontwarn com.stripe.android.pushProvisioning.**
-dontwarn com.reactnativestripesdk.pushprovisioning.**
