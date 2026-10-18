import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        background: "var(--background)",
        foreground: "var(--foreground)",
        brand: {
          50: "#eef4ff",
          100: "#dae6ff",
          200: "#bdd3ff",
          300: "#90b6ff",
          400: "#5c8dff",
          500: "#3567f6",
          600: "#1f47eb",
          700: "#1a37d4",
          800: "#1c31ab",
          900: "#1c2f87",
          950: "#151e53",
        },
        ink: {
          50: "#f6f7f9",
          100: "#eceef2",
          200: "#d5dae3",
          300: "#b0bacb",
          400: "#8593ab",
          500: "#657590",
          600: "#505d76",
          700: "#424c60",
          800: "#3a4152",
          900: "#343a48",
          950: "#22262f",
        },
      },
      fontFamily: {
        sans: ["var(--font-inter)", "Inter", "system-ui", "sans-serif"],
      },
      boxShadow: {
        xs: "0 1px 2px 0 rgb(16 24 40 / 0.05)",
        soft: "0 1px 2px 0 rgb(16 24 40 / 0.04), 0 4px 12px -2px rgb(16 24 40 / 0.07)",
        card: "0 1px 3px 0 rgb(16 24 40 / 0.05), 0 10px 28px -8px rgb(16 24 40 / 0.12)",
        lift: "0 2px 4px -1px rgb(16 24 40 / 0.05), 0 18px 40px -12px rgb(16 24 40 / 0.20)",
        ring: "0 0 0 1px rgb(31 71 235 / 0.08), 0 0 0 4px rgb(53 103 246 / 0.10)",
        gloss: "inset 0 1px 0 0 rgb(255 255 255 / 0.55)",
        "gloss-strong": "inset 0 1px 0 0 rgb(255 255 255 / 0.75)",
        glow: "0 8px 30px -6px rgb(31 71 235 / 0.45)",
      },
      backgroundImage: {
        "brand-gradient":
          "linear-gradient(135deg, #5c8dff 0%, #3567f6 45%, #1f47eb 100%)",
        "brand-sheen":
          "linear-gradient(180deg, rgb(255 255 255 / 0.28) 0%, rgb(255 255 255 / 0) 55%)",
        "surface":
          "linear-gradient(180deg, #ffffff 0%, #fdfdfe 60%, #fbfcfe 100%)",
        "glass-dark":
          "linear-gradient(160deg, rgb(255 255 255 / 0.10) 0%, rgb(255 255 255 / 0.03) 55%, rgb(255 255 255 / 0.06) 100%)",
      },
      keyframes: {
        "fade-up": {
          from: { opacity: "0", transform: "translateY(8px)" },
          to: { opacity: "1", transform: "translateY(0)" },
        },
        "fade-in": {
          from: { opacity: "0" },
          to: { opacity: "1" },
        },
        "scale-in": {
          from: { opacity: "0", transform: "scale(0.96) translateY(6px)" },
          to: { opacity: "1", transform: "scale(1) translateY(0)" },
        },
        "slide-in-right": {
          from: { opacity: "0", transform: "translateX(16px)" },
          to: { opacity: "1", transform: "translateX(0)" },
        },
        shimmer: {
          "100%": { transform: "translateX(100%)" },
        },
        "pulse-ring": {
          "0%": { boxShadow: "0 0 0 0 rgb(31 71 235 / 0.35)" },
          "70%": { boxShadow: "0 0 0 8px rgb(31 71 235 / 0)" },
          "100%": { boxShadow: "0 0 0 0 rgb(31 71 235 / 0)" },
        },
        float: {
          "0%, 100%": { transform: "translateY(0)" },
          "50%": { transform: "translateY(-6px)" },
        },
        "gradient-x": {
          "0%, 100%": { backgroundPosition: "0% 50%" },
          "50%": { backgroundPosition: "100% 50%" },
        },
      },
      animation: {
        "fade-up": "fade-up 0.45s cubic-bezier(0.16, 1, 0.3, 1) both",
        "fade-in": "fade-in 0.35s ease-out both",
        "scale-in": "scale-in 0.28s cubic-bezier(0.16, 1, 0.3, 1) both",
        "slide-in-right": "slide-in-right 0.3s cubic-bezier(0.16, 1, 0.3, 1) both",
        shimmer: "shimmer 1.8s infinite",
        "pulse-ring": "pulse-ring 2s cubic-bezier(0.4, 0, 0.6, 1) infinite",
        float: "float 6s ease-in-out infinite",
        "gradient-x": "gradient-x 8s ease infinite",
      },
      transitionTimingFunction: {
        spring: "cubic-bezier(0.16, 1, 0.3, 1)",
      },
    },
  },
  plugins: [],
};
export default config;