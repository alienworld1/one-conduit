import { ProductTable } from "@/components/ProductTable";
import { PageWrapper } from "@/components/PageWrapper";

export default function HomePage() {
  return (
    <PageWrapper>
      <div className="mx-auto w-full max-w-7xl px-4 md:px-6">
        <ProductTable />
      </div>
    </PageWrapper>
  );
}
