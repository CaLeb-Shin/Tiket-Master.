importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyB2IUcsdvC5V0ZnSb99czMRcFsaDIjwlhA',
  appId: '1:587640969766:web:636501198faa67c56564e7',
  messagingSenderId: '587640969766',
  projectId: 'melon-ticket-mvp-2026',
  authDomain: 'melon-ticket-mvp-2026.firebaseapp.com',
  storageBucket: 'melon-ticket-mvp-2026.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  const notificationTitle = payload.notification?.title || '멜론티켓';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data,
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
