import { useEffect, useMemo, useState } from "react";

import { apiRequest } from "../api";
import TransactionForm from "../components/TransactionForm";
import TransactionTable from "../components/TransactionTable";


export default function DashboardPage({ user, token }) {
  const [transactions, setTransactions] = useState([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadTransactions() {
      setLoading(true);
      setError("");

      try {
        const data = await apiRequest("/transactions", {}, token);
        setTransactions(data.transactions);
      } catch (requestError) {
        setError(requestError.message);
      } finally {
        setLoading(false);
      }
    }

    loadTransactions();
  }, [token]);

  function handleTransactionCreated(transaction) {
    setTransactions((currentTransactions) => [transaction, ...currentTransactions]);
  }

  const totalSubmitted = useMemo(() => {
    return transactions.reduce((sum, transaction) => sum + Number(transaction.amount), 0);
  }, [transactions]);

  return (
    <main className="page-content dashboard-layout">
      <section className="hero-grid">
        <div className="panel hero-panel">
          <p className="eyebrow">Account overview</p>
          <h1>{user ? `Hello, ${user.full_name}` : "Your dashboard"}</h1>
          <p className="hero-copy">
            This MVP focuses on the core fintech flow: authentication, dashboard access,
            payment submission, and transaction history.
          </p>
        </div>

        <div className="summary-card">
          <p>Total submitted</p>
          <strong>
            {new Intl.NumberFormat("en-US", {
              style: "currency",
              currency: "USD",
            }).format(totalSubmitted)}
          </strong>
          <span>{transactions.length} recorded transaction(s)</span>
        </div>
      </section>

      <TransactionForm
        onTransactionCreated={handleTransactionCreated}
        token={token}
      />

      {error ? (
        <section className="panel">
          <p className="form-error">{error}</p>
        </section>
      ) : null}

      {loading ? (
        <section className="panel">
          <p>Loading transactions...</p>
        </section>
      ) : (
        <TransactionTable transactions={transactions} />
      )}
    </main>
  );
}
