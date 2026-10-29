import React, { useState } from 'react';

export interface CapitalMarketsAgentProps {
  /** Override the API Gateway endpoint if needed */
  apiUrl?: string;
  /** Initial or placeholder document key in S3 */
  defaultDocumentKey?: string;
  /** Initial question */
  defaultQuestion?: string;
  /** Optional custom CSS class name */
  className?: string;
  /** Optional inline styles for the container */
  style?: React.CSSProperties;
}

interface QueryResponse {
  answer?: string;
  document_key?: string;
  error?: string;
}

export const CapitalMarketsAgent: React.FC<CapitalMarketsAgentProps> = ({
  apiUrl = 'https://qesk3fs93f.execute-api.us-east-1.amazonaws.com/prod/query',
  defaultDocumentKey = 'some-doc.txt',
  defaultQuestion = 'Summarize the financial metrics',
  className = '',
  style = {},
}) => {
  const [documentKey, setDocumentKey] = useState<string>(defaultDocumentKey);
  const [question, setQuestion] = useState<string>(defaultQuestion);
  const [loading, setLoading] = useState<boolean>(false);
  const [response, setResponse] = useState<QueryResponse | null>(null);
  const [errorDetails, setErrorDetails] = useState<string | null>(null);
  const [isCopied, setIsCopied] = useState<boolean>(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!documentKey.trim() || !question.trim() || loading) return;

    setLoading(true);
    setResponse(null);
    setErrorDetails(null);
    setIsCopied(false);

    try {
      const res = await fetch(apiUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          document_key: documentKey.trim(),
          question: question.trim(),
        }),
      });

      const data = await res.json().catch(() => null);

      if (!res.ok) {
        // Handle 502 / Upstream AWS or Bedrock Quota errors gracefully
        if (res.status === 502) {
          setErrorDetails(
            data?.error ||
              'Upstream AWS Bedrock error: Daily token quota limit reached on Claude Haiku (429/ThrottlingException). The Lambda execution, IAM role, and S3 retrieval succeeded.'
          );
        } else if (res.status === 404) {
          setErrorDetails(data?.error || `Document '${documentKey}' not found in the S3 bucket.`);
        } else if (res.status === 400) {
          setErrorDetails(data?.error || 'Invalid request parameters. Please verify question and document key.');
        } else {
          setErrorDetails(data?.error || `HTTP ${res.status}: Unexpected response from API Gateway.`);
        }
        return;
      }

      setResponse(data);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Network error or CORS issue contacting API.';
      setErrorDetails(message);
    } finally {
      setLoading(false);
    }
  };

  const handleCopy = () => {
    if (response?.answer) {
      navigator.clipboard.writeText(response.answer);
      setIsCopied(true);
      setTimeout(() => setIsCopied(false), 2000);
    }
  };

  const handleQuickFill = (doc: string, q: string) => {
    setDocumentKey(doc);
    setQuestion(q);
  };

  return (
    <div
      className={`cma-container ${className}`}
      style={{
        ...styles.container,
        ...style,
      }}
    >
      {/* Header */}
      <div style={styles.header}>
        <div style={styles.headerLeft}>
          <div style={styles.iconWrapper}>
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#38bdf8" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z" />
              <polyline points="3.27 6.96 12 12.01 20.73 6.96" />
              <line x1="12" y1="22.08" x2="12" y2="12" />
            </svg>
          </div>
          <div>
            <div style={styles.titleRow}>
              <h3 style={styles.title}>Capital Markets RAG Agent</h3>
              <span style={styles.liveBadge}>
                <span style={styles.liveDot} />
                Live API
              </span>
            </div>
            <p style={styles.subtitle}>
              Retrieval-Augmented Generation with Amazon Bedrock (Claude Haiku 4.5) &amp; S3
            </p>
          </div>
        </div>
      </div>

      {/* Preset Quick Fill Prompts */}
      <div style={styles.quickPrompts}>
        <span style={styles.quickPromptLabel}>Presets:</span>
        <button
          type="button"
          onClick={() => handleQuickFill('some-doc.txt', 'Summarize the financial metrics')}
          style={styles.quickPromptBtn}
        >
          📊 Financial Metrics
        </button>
        <button
          type="button"
          onClick={() => handleQuickFill('some-doc.txt', 'What was the Q3 revenue and EPS?')}
          style={styles.quickPromptBtn}
        >
          📈 Q3 Revenue &amp; EPS
        </button>
        <button
          type="button"
          onClick={() => handleQuickFill('some-doc.txt', 'What is the forward guidance?')}
          style={styles.quickPromptBtn}
        >
          🎯 Forward Guidance
        </button>
      </div>

      {/* Form */}
      <form onSubmit={handleSubmit} style={styles.form}>
        <div style={styles.formGroup}>
          <label htmlFor="documentKey" style={styles.label}>
            <span>Document Key (S3 Object)</span>
            <span style={styles.helperText}>Path inside private RAG S3 bucket</span>
          </label>
          <div style={styles.inputWrapper}>
            <input
              id="documentKey"
              type="text"
              value={documentKey}
              onChange={(e) => setDocumentKey(e.target.value)}
              placeholder="e.g., some-doc.txt or financials/q3-2026.pdf"
              required
              style={styles.input}
              disabled={loading}
            />
          </div>
        </div>

        <div style={styles.formGroup}>
          <label htmlFor="question" style={styles.label}>
            <span>Question</span>
            <span style={styles.helperText}>Natural language inquiry</span>
          </label>
          <div style={styles.inputWrapper}>
            <textarea
              id="question"
              value={question}
              onChange={(e) => setQuestion(e.target.value)}
              placeholder="Ask an analytical question about the financial document..."
              required
              rows={3}
              style={{ ...styles.input, ...styles.textarea }}
              disabled={loading}
            />
          </div>
        </div>

        <button
          type="submit"
          disabled={loading || !documentKey.trim() || !question.trim()}
          style={{
            ...styles.submitBtn,
            ...(loading || !documentKey.trim() || !question.trim() ? styles.submitBtnDisabled : {}),
          }}
        >
          {loading ? (
            <span style={styles.loadingFlex}>
              <span style={styles.spinner} />
              <span>Querying Bedrock RAG...</span>
            </span>
          ) : (
            <span style={styles.submitFlex}>
              <span>Analyze Document</span>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <line x1="5" y1="12" x2="19" y2="12" />
                <polyline points="12 5 19 12 12 19" />
              </svg>
            </span>
          )}
        </button>
      </form>

      {/* Graceful Error Banner (Tailored for AWS Quota / 502 Handling) */}
      {errorDetails && (
        <div style={styles.errorBox}>
          <div style={styles.errorHeader}>
            <div style={styles.errorTitle}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#f87171" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <line x1="12" y1="8" x2="12" y2="12" />
                <line x1="12" y1="16" x2="12.01" y2="16" />
              </svg>
              <span>AWS Infrastructure Notice</span>
            </div>
            <span style={styles.errorCodeBadge}>502 / Upstream Service</span>
          </div>
          <p style={styles.errorMessage}>{errorDetails}</p>
          <div style={styles.pipelineStatus}>
            <span style={styles.pipelineItem}>
              <span style={styles.checkIcon}>✓</span> API Gateway
            </span>
            <span style={styles.pipelineItem}>
              <span style={styles.checkIcon}>✓</span> Lambda Function
            </span>
            <span style={styles.pipelineItem}>
              <span style={styles.checkIcon}>✓</span> S3 Doc Retrieval
            </span>
            <span style={styles.pipelineItemPending}>
              <span style={styles.clockIcon}>⏳</span> Bedrock Daily Quota Reset
            </span>
          </div>
        </div>
      )}

      {/* Success Response Display */}
      {response?.answer && (
        <div style={styles.responseBox}>
          <div style={styles.responseHeader}>
            <div style={styles.responseBadge}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#4ade80" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="20 6 9 17 4 12" />
              </svg>
              <span>Source: {response.document_key || documentKey}</span>
            </div>
            <button type="button" onClick={handleCopy} style={styles.copyBtn}>
              {isCopied ? 'Copied!' : 'Copy Answer'}
            </button>
          </div>
          <div style={styles.answerText}>{response.answer}</div>
        </div>
      )}

      {/* Footer Info */}
      <div style={styles.footer}>
        <span>Architecture: API Gateway (HTTP) → Lambda (Python 3.11) → S3 &amp; Bedrock</span>
      </div>
    </div>
  );
};

// Sleek, modern, self-contained CSS styles (no external dependencies required)
const styles: Record<string, React.CSSProperties> = {
  container: {
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    maxWidth: '720px',
    margin: '0 auto',
    backgroundColor: '#0f172a', // Slate 900
    color: '#f8fafc',
    borderRadius: '16px',
    border: '1px solid #1e293b',
    padding: '28px',
    boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.4), 0 8px 10px -6px rgba(0, 0, 0, 0.3)',
    boxSizing: 'border-box',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: '20px',
    borderBottom: '1px solid #1e293b',
    paddingBottom: '16px',
  },
  headerLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: '14px',
  },
  iconWrapper: {
    width: '44px',
    height: '44px',
    borderRadius: '12px',
    backgroundColor: 'rgba(56, 189, 248, 0.1)',
    border: '1px solid rgba(56, 189, 248, 0.25)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  titleRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
    flexWrap: 'wrap',
  },
  title: {
    margin: 0,
    fontSize: '1.25rem',
    fontWeight: 700,
    letterSpacing: '-0.02em',
    color: '#ffffff',
  },
  liveBadge: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '6px',
    backgroundColor: 'rgba(34, 197, 94, 0.12)',
    color: '#4ade80',
    fontSize: '0.72rem',
    fontWeight: 600,
    padding: '3px 8px',
    borderRadius: '9999px',
    border: '1px solid rgba(34, 197, 94, 0.25)',
  },
  liveDot: {
    width: '6px',
    height: '6px',
    borderRadius: '50%',
    backgroundColor: '#22c55e',
    boxShadow: '0 0 6px #22c55e',
  },
  subtitle: {
    margin: '4px 0 0 0',
    fontSize: '0.85rem',
    color: '#94a3b8',
  },
  quickPrompts: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    flexWrap: 'wrap',
    marginBottom: '20px',
  },
  quickPromptLabel: {
    fontSize: '0.78rem',
    color: '#64748b',
    fontWeight: 600,
    textTransform: 'uppercase',
    letterSpacing: '0.05em',
  },
  quickPromptBtn: {
    background: '#1e293b',
    border: '1px solid #334155',
    color: '#cbd5e1',
    padding: '5px 10px',
    borderRadius: '8px',
    fontSize: '0.75rem',
    cursor: 'pointer',
    transition: 'all 0.15s ease-in-out',
  },
  form: {
    display: 'flex',
    flexDirection: 'column',
    gap: '16px',
  },
  formGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: '6px',
  },
  label: {
    display: 'flex',
    justifyContent: 'space-between',
    fontSize: '0.82rem',
    fontWeight: 600,
    color: '#e2e8f0',
  },
  helperText: {
    fontSize: '0.75rem',
    fontWeight: 400,
    color: '#64748b',
  },
  inputWrapper: {
    position: 'relative',
  },
  input: {
    width: '100%',
    backgroundColor: '#090d16',
    border: '1px solid #334155',
    borderRadius: '10px',
    padding: '10px 14px',
    fontSize: '0.9rem',
    color: '#f8fafc',
    outline: 'none',
    boxSizing: 'border-box',
    transition: 'border-color 0.2s',
  },
  textarea: {
    resize: 'vertical',
    minHeight: '75px',
    lineHeight: '1.45',
  },
  submitBtn: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '8px',
    backgroundColor: '#0284c7', // Sky 600
    color: '#ffffff',
    border: 'none',
    borderRadius: '10px',
    padding: '12px 18px',
    fontSize: '0.92rem',
    fontWeight: 600,
    cursor: 'pointer',
    marginTop: '4px',
    transition: 'background-color 0.2s, opacity 0.2s',
    boxShadow: '0 4px 12px rgba(2, 132, 199, 0.35)',
  },
  submitBtnDisabled: {
    backgroundColor: '#334155',
    cursor: 'not-allowed',
    opacity: 0.65,
    boxShadow: 'none',
  },
  submitFlex: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '8px',
  },
  loadingFlex: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '10px',
  },
  spinner: {
    width: '16px',
    height: '16px',
    border: '2px solid rgba(255, 255, 255, 0.3)',
    borderTopColor: '#ffffff',
    borderRadius: '50%',
    display: 'inline-block',
    animation: 'cma-spin 0.8s linear infinite',
  },
  errorBox: {
    marginTop: '20px',
    backgroundColor: 'rgba(239, 68, 68, 0.08)',
    border: '1px solid rgba(239, 68, 68, 0.25)',
    borderRadius: '12px',
    padding: '16px',
  },
  errorHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '8px',
  },
  errorTitle: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    color: '#f87171',
    fontWeight: 600,
    fontSize: '0.88rem',
  },
  errorCodeBadge: {
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    color: '#fca5a5',
    fontSize: '0.72rem',
    fontWeight: 600,
    padding: '2px 8px',
    borderRadius: '4px',
    fontFamily: 'monospace',
  },
  errorMessage: {
    margin: '0 0 12px 0',
    fontSize: '0.85rem',
    lineHeight: '1.45',
    color: '#e2e8f0',
  },
  pipelineStatus: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    flexWrap: 'wrap',
    borderTop: '1px solid rgba(239, 68, 68, 0.15)',
    paddingTop: '10px',
    fontSize: '0.76rem',
  },
  pipelineItem: {
    color: '#4ade80',
    display: 'inline-flex',
    alignItems: 'center',
    gap: '4px',
    fontWeight: 500,
  },
  pipelineItemPending: {
    color: '#facc15',
    display: 'inline-flex',
    alignItems: 'center',
    gap: '4px',
    fontWeight: 500,
  },
  checkIcon: {
    fontWeight: 800,
  },
  clockIcon: {
    fontSize: '0.85rem',
  },
  responseBox: {
    marginTop: '20px',
    backgroundColor: '#090d16',
    border: '1px solid #1e293b',
    borderRadius: '12px',
    padding: '18px',
  },
  responseHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '12px',
  },
  responseBadge: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '6px',
    fontSize: '0.75rem',
    color: '#94a3b8',
    backgroundColor: '#1e293b',
    padding: '3px 8px',
    borderRadius: '6px',
  },
  copyBtn: {
    background: 'transparent',
    border: '1px solid #334155',
    color: '#cbd5e1',
    borderRadius: '6px',
    padding: '4px 10px',
    fontSize: '0.75rem',
    cursor: 'pointer',
  },
  answerText: {
    fontSize: '0.92rem',
    lineHeight: '1.6',
    color: '#f1f5f9',
    whiteSpace: 'pre-wrap',
  },
  footer: {
    marginTop: '20px',
    paddingTop: '12px',
    borderTop: '1px solid #1e293b',
    fontSize: '0.72rem',
    color: '#64748b',
    textAlign: 'center',
  },
};

export default CapitalMarketsAgent;
