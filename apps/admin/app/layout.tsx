import type { Metadata, Viewport } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { Toaster } from 'react-hot-toast'

const inter = Inter({ subsets: ['latin'], display: 'swap', variable: '--font-inter' })

export const metadata: Metadata = {
  title: 'SCORE+ Admin',
  description: 'SCORE+ Mentor Desk — Administration Dashboard',
  robots: 'noindex, nofollow', // Admin DMS must not be indexed
}

export const viewport: Viewport = {
  themeColor: '#151e53',
  colorScheme: 'light',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className={inter.variable}>
      <body className={`${inter.className} antialiased`}>
        {children}
        <Toaster
          position="top-right"
          gutter={10}
          toastOptions={{
            duration: 4000,
            className:
              'rounded-xl border border-ink-200/70 bg-white/95 px-4 py-3 text-sm font-medium text-ink-800 shadow-lift backdrop-blur-md',
            success: { iconTheme: { primary: '#10b981', secondary: '#ffffff' } },
            error: { iconTheme: { primary: '#e11d48', secondary: '#ffffff' } },
          }}
        />
      </body>
    </html>
  )
}