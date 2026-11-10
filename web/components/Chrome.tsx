import Link from "next/link";
import { REPO_URL } from "@/lib/site";

export function GitHubMark() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 .5C5.65.5.5 5.65.5 12a11.5 11.5 0 0 0 7.86 10.92c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.36-3.88-1.36-.52-1.33-1.28-1.68-1.28-1.68-1.05-.72.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.55-.29-5.24-1.28-5.24-5.69 0-1.26.45-2.29 1.19-3.1-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.18 1.18a11 11 0 0 1 5.79 0c2.2-1.49 3.17-1.18 3.17-1.18.64 1.59.24 2.76.12 3.05.74.81 1.19 1.84 1.19 3.1 0 4.42-2.7 5.4-5.26 5.68.42.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5Z" />
    </svg>
  );
}

export function GitHubButton({ primary = false }: { primary?: boolean }) {
  return (
    <a className={`button${primary ? " primary" : ""}`} href={REPO_URL}>
      <GitHubMark />
      Get the source
    </a>
  );
}

export function Nav() {
  return (
    <header className="nav row">
      <Link href="/" className="wordmark">
        <i />
        OpenFM
      </Link>
      <nav aria-label="Site">
        <Link href="/guide">Guide</Link>
        <a href={REPO_URL}>GitHub</a>
      </nav>
    </header>
  );
}

export function Footer() {
  return (
    <footer className="footer">
      <span>OpenFM · Apache 2.0 · FM core by Google MSFA · set in Geist</span>
      <span>
        <Link href="/guide">Guide</Link> · <a href={REPO_URL}>GitHub</a>
      </span>
    </footer>
  );
}
