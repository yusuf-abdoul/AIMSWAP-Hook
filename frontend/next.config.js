/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  webpack: (config, { isServer }) => {
    // Enable WebAssembly support for cofhejs
    config.experiments = {
      ...config.experiments,
      asyncWebAssembly: true,
      layers: true,
    };

    // Handle .wasm files
    config.module.rules.push({
      test: /\.wasm$/,
      type: 'asset/resource',
      generator: {
        filename: 'static/wasm/[name].[hash][ext]',
      },
    });

    // Client-side: cofhejs/web is used for FHE encryption with user's wallet
    if (!isServer) {
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        net: false,
        tls: false,
        stream: false,
        http: false,
        https: false,
        zlib: false,
        path: false,
        os: false,
        'pino-pretty': false,
        '@react-native-async-storage/async-storage': false,
      };
    }

    return config;
  },
  // Server-side components can use cofhejs/node directly
  experimental: {
    serverComponentsExternalPackages: ['cofhejs'],
  },
};

module.exports = nextConfig;
