function formatAmount(value) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
  }).format(value);
}


function formatDate(value) {
  return new Date(value).toLocaleString();
}


export default function TransactionTable({ transactions }) {
  return (
    <section className="panel">
      <div className="panel-header">
        <div>
          <h2>Recent transactions</h2>
          <p>Your latest submitted activity appears below.</p>
        </div>
      </div>

      {transactions.length === 0 ? (
        <p className="empty-state">No transactions yet. Submit your first payment above.</p>
      ) : (
        <div className="table-wrapper">
          <table>
            <thead>
              <tr>
                <th>Recipient</th>
                <th>Type</th>
                <th>Amount</th>
                <th>Status</th>
                <th>Reference</th>
                <th>Created</th>
              </tr>
            </thead>
            <tbody>
              {transactions.map((transaction) => (
                <tr key={transaction.id}>
                  <td>{transaction.recipient_name}</td>
                  <td className="capitalize">{transaction.transaction_type}</td>
                  <td>{formatAmount(transaction.amount)}</td>
                  <td>
                    <span className="status-pill">{transaction.status}</span>
                  </td>
                  <td>{transaction.reference || "-"}</td>
                  <td>{formatDate(transaction.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
