import { MD3LightTheme, MD3DarkTheme, MD3Theme } from 'react-native-paper';

/**
 * PAI Mobile — Material 3 Design Tokens
 *
 * Based on Material 3 (https://m3.material.io/)
 * Adapted for PAI identity: calm, authoritative, voice-first.
 */

const paiColorTokens = {
  light: {
    primary: '#3B82F6',
    onPrimary: '#FFFFFF',
    primaryContainer: '#D6E4FF',
    onPrimaryContainer: '#001D36',
    secondary: '#5C5B5F',
    onSecondary: '#FFFFFF',
    secondaryContainer: '#E4E1E6',
    onSecondaryContainer: '#1A1C1E',
    tertiary: '#006C4C',
    onTertiary: '#FFFFFF',
    tertiaryContainer: '#66FEB8',
    onTertiaryContainer: '#002114',
    error: '#BA1A1A',
    onError: '#FFFFFF',
    errorContainer: '#FFDAD6',
    onErrorContainer: '#410002',
    background: '#FDFCFF',
    onBackground: '#1A1C1E',
    surface: '#FDFCFF',
    onSurface: '#1A1C1E',
    surfaceVariant: '#E4E1E6',
    onSurfaceVariant: '#46464F',
    outline: '#767680',
    outlineVariant: '#C6C5D0',
    shadow: '#000000',
    scrim: '#000000',
    inverseSurface: '#2E3033',
    inverseOnSurface: '#F1F0F4',
    inversePrimary: '#A0C9FF',
    elevation: {
      level0: 'transparent',
      level1: '#F4F4F8',
      level2: '#EEEEF4',
      level3: '#E9E9F1',
      level4: '#E7E7EF',
      level5: '#E3E3EC',
    },
    surfaceDisabled: 'rgba(26, 28, 30, 0.12)',
    onSurfaceDisabled: 'rgba(26, 28, 30, 0.38)',
    backdrop: 'rgba(46, 48, 56, 0.4)',
  },
  dark: {
    primary: '#A0C9FF',
    onPrimary: '#003258',
    primaryContainer: '#00497D',
    onPrimaryContainer: '#D6E4FF',
    secondary: '#C7C6CA',
    onSecondary: '#303033',
    secondaryContainer: '#46464F',
    onSecondaryContainer: '#E4E1E6',
    tertiary: '#49DB9D',
    onTertiary: '#003826',
    tertiaryContainer: '#005138',
    onTertiaryContainer: '#66FEB8',
    error: '#FFB4AB',
    onError: '#690005',
    errorContainer: '#93000A',
    onErrorContainer: '#FFDAD6',
    background: '#1A1C1E',
    onBackground: '#E3E2E6',
    surface: '#1A1C1E',
    onSurface: '#E3E2E6',
    surfaceVariant: '#46464F',
    onSurfaceVariant: '#C6C5D0',
    outline: '#90909A',
    outlineVariant: '#46464F',
    shadow: '#000000',
    scrim: '#000000',
    inverseSurface: '#E3E2E6',
    inverseOnSurface: '#2E3033',
    inversePrimary: '#3B82F6',
    elevation: {
      level0: 'transparent',
      level1: '#212328',
      level2: '#26282D',
      level3: '#2B2D32',
      level4: '#2D2F34',
      level5: '#303236',
    },
    surfaceDisabled: 'rgba(227, 226, 230, 0.12)',
    onSurfaceDisabled: 'rgba(227, 226, 230, 0.38)',
    backdrop: 'rgba(46, 48, 56, 0.4)',
  },
};

export const paiLightTheme: MD3Theme = {
  ...MD3LightTheme,
  colors: {
    ...MD3LightTheme.colors,
    ...paiColorTokens.light,
  },
};

export const paiDarkTheme: MD3Theme = {
  ...MD3DarkTheme,
  colors: {
    ...MD3DarkTheme.colors,
    ...paiColorTokens.dark,
  },
};

/**
 * Default exported theme (light).
 * The app will later switch between light/dark via appStore.
 */
export const paiTheme = paiLightTheme;

export type PAITheme = typeof paiTheme;
