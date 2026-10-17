import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { Toaster } from 'react-hot-toast'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'TeachCross Admin',
  description: 'School Communication Platform — Administration Dashboard',
  robots: 'noindex, nofollow', // Admin DMS must not be indexed
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className={inter.className}>
        {children}
        <Toaster
          position="top-right"
          toastOptions={{
            duration: 4000,
            style: {
              borderRadius: '10px',
              background: '#1F2937',
              color: '#F9FAFB',
            },
          }}
        />
      </body>
    </html>
  )
}
