import { ProductTable } from "@/components/ProductTable";
import { PageWrapper } from "@/components/PageWrapper";
import { ErrorBoundary } from "@/components/ErrorBoundary";
import { ProductPageHeader } from "@/components/ProductPageHeader";
import { HowItWorks } from "@/components/HowItWorks";

export default function HomePage() {
  return (
    <PageWrapper>
      <ErrorBoundary>
        <div className="mx-auto w-full max-w-7xl px-4 py-16 md:px-6">
          <ProductPageHeader />
          <HowItWorks />
          <ProductTable />
        </div>
      </ErrorBoundary>
    </PageWrapper>
  );
}
