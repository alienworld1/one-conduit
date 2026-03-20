import { ProductTable } from "@/components/ProductTable";
import { PageWrapper } from "@/components/PageWrapper";
import { ErrorBoundary } from "@/components/ErrorBoundary";

export default function HomePage() {
  return (
    <PageWrapper>
      <ErrorBoundary>
        <div className="mx-auto w-full max-w-7xl px-4 md:px-6">
          <ProductTable />
        </div>
      </ErrorBoundary>
    </PageWrapper>
  );
}
