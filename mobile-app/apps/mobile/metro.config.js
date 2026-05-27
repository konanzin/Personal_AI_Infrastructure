const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const config = getDefaultConfig(__dirname);

// Monorepo support: watch workspace packages for live reload
const monorepoPackages = [
  path.resolve(__dirname, '../../packages/shared-types'),
  path.resolve(__dirname, '../../packages/shared-schemas'),
  path.resolve(__dirname, '../../packages/ui-system'),
  path.resolve(__dirname, '../../packages/opencode-mobile-client'),
  path.resolve(__dirname, '../../packages/audio-elevenlabs'),
  path.resolve(__dirname, '../../packages/test-utils'),
];

config.watchFolders = [...(config.watchFolders || []), ...monorepoPackages];

// Ensure Metro resolves workspace packages
config.resolver.nodeModulesPaths = [
  path.resolve(__dirname, 'node_modules'),
  path.resolve(__dirname, '../../node_modules'),
];

// Expo Go on this Samsung/Expo combination crashes while initializing the
// optional react-native-reanimated peer pulled in by expo-router, even though
// the app does not use it. Force Metro to resolve it to a harmless shim.
config.resolver.extraNodeModules = {
  ...(config.resolver.extraNodeModules || {}),
  'react-native-reanimated': path.resolve(
    __dirname,
    './src/shims/react-native-reanimated.js'
  ),
};

module.exports = config;
