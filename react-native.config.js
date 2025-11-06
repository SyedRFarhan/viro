module.exports = {
  dependencies: {
    // Exclude expo from autolinking since it's a peer dependency
    expo: {
      platforms: {
        android: null,
        ios: null,
      },
    },
  },
};
