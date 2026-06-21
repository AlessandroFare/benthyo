import { useEffect, useState } from "react";
import {
  CreditCard,
  Download,
  FileSignature,
  Settings,
  UserPlus,
  Users,
} from "lucide-react";
import {
  useCreatePaymentLink,
  useOperatorWaiver,
  usePaymentLinks,
  useUpsertWaiver,
} from "@/hooks/useCompliance";
import {
  useExportCsv,
  useInviteTeamMember,
  useSettings,
  useUpdateOperator,
} from "@/hooks/useSettings";
import { EmptyState } from "@/components/shared/EmptyState";
import { PageSkeleton } from "@/components/shared/LoadingSkeleton";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { formatDate } from "@/lib/utils";
import type { TeamMember } from "@/lib/types";

const tierLabels: Record<string, string> = {
  free: "Free",
  starter: "Starter",
  pro: "Pro",
  enterprise: "Enterprise",
};

const statusVariants: Record<string, "success" | "warning" | "destructive" | "secondary"> = {
  active: "success",
  trialing: "secondary",
  past_due: "warning",
  cancelled: "destructive",
};

export function SettingsPage() {
  const { data, isLoading, isError, refetch } = useSettings();
  const updateOperator = useUpdateOperator();
  const inviteMember = useInviteTeamMember();
  const exportCsv = useExportCsv();
  const waiverQuery = useOperatorWaiver();
  const upsertWaiver = useUpsertWaiver();
  const paymentLinks = usePaymentLinks();
  const createPaymentLink = useCreatePaymentLink();

  const [waiverTitle, setWaiverTitle] = useState("Liability waiver");
  const [waiverBody, setWaiverBody] = useState("");
  const [payAmount, setPayAmount] = useState("5000");
  const [payDesc, setPayDesc] = useState("Dive deposit");
  const [payUrl, setPayUrl] = useState("");
  const [stripeWebhookUrl, setStripeWebhookUrl] = useState("");
  const [stripeWebhookErr, setStripeWebhookErr] = useState<string | null>(null);

  // Validate the webhook URL on every keystroke. Only `https://` and a
  // `stripe.com` host (or subdomains) are accepted; this prevents a
  // operator from accidentally pasting a phishing link here.
  function validateWebhookUrl(raw: string): string | null {
    if (raw.length === 0) return null;
    let parsed: URL;
    try {
      parsed = new URL(raw);
    } catch {
      return 'Must be a valid URL';
    }
    if (parsed.protocol !== 'https:') {
      return 'Webhook URL must use HTTPS';
    }
    const host = parsed.hostname.toLowerCase();
    const allowed = host === 'stripe.com' || host.endsWith('.stripe.com');
    if (!allowed) {
      return 'Webhook URL must be on stripe.com';
    }
    return null;
  }

  const [inviteOpen, setInviteOpen] = useState(false);
  const [inviteUserId, setInviteUserId] = useState("");
  const [inviteRole, setInviteRole] = useState<TeamMember["role"]>("staff");

  const [name, setName] = useState("");
  const [website, setWebsite] = useState("");
  const [region, setRegion] = useState("");

  useEffect(() => {
    if (data) {
      setName(data.operator.name);
      setWebsite(data.operator.website ?? "");
      setRegion(data.operator.region);
    }
  }, [data]);

  useEffect(() => {
    if (waiverQuery.data?.waiver) {
      setWaiverTitle(waiverQuery.data.waiver.title);
      setWaiverBody(waiverQuery.data.waiver.body);
    }
  }, [waiverQuery.data]);

  if (isLoading) {
    return <PageSkeleton />;
  }

  if (isError || !data) {
    return (
      <EmptyState
        icon={Settings}
        title="Settings unavailable"
        description="Could not load your operator settings."
        actionLabel="Retry"
        onAction={() => refetch()}
      />
    );
  }

  async function handleSaveProfile() {
    await updateOperator.mutateAsync({
      name,
      website: website || null,
      region,
    });
  }

  async function handleInvite() {
    if (!inviteUserId.trim()) return;
    await inviteMember.mutateAsync({
      user_id: inviteUserId.trim(),
      role: inviteRole,
    });
    setInviteUserId("");
    setInviteOpen(false);
  }

  async function handleExport(type: "customers" | "sightings" | "dives") {
    const result = await exportCsv.mutateAsync(type);
    if (result.download_url) {
      window.open(result.download_url, "_blank");
    }
  }

  return (
    <div className="space-y-6">
      <Tabs defaultValue="profile">
        <TabsList>
          <TabsTrigger value="profile">Operator Profile</TabsTrigger>
          <TabsTrigger value="team">Team</TabsTrigger>
          <TabsTrigger value="subscription">Subscription</TabsTrigger>
          <TabsTrigger value="export">CSV Export</TabsTrigger>
          <TabsTrigger value="compliance">Compliance</TabsTrigger>
        </TabsList>

        <TabsContent value="profile" className="mt-6">
          <Card>
            <CardHeader>
              <CardTitle>Operator Profile</CardTitle>
              <CardDescription>
                Update your dive center information
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="name">Business Name</Label>
                  <Input
                    id="name"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="email">Email</Label>
                  <Input
                    id="email"
                    value={data.operator.email ?? ""}
                    disabled
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="website">Website</Label>
                  <Input
                    id="website"
                    value={website}
                    onChange={(e) => setWebsite(e.target.value)}
                    placeholder="https://"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="region">Region</Label>
                  <Input
                    id="region"
                    value={region}
                    onChange={(e) => setRegion(e.target.value)}
                  />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Country</Label>
                <Input value={data.operator.country_code ?? ""} disabled />
              </div>
              <Button
                onClick={handleSaveProfile}
                disabled={updateOperator.isPending}
              >
                {updateOperator.isPending ? "Saving..." : "Save Changes"}
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="team" className="mt-6">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between">
              <div>
                <CardTitle>Team Members</CardTitle>
                <CardDescription>
                  Manage who has access to this dashboard
                </CardDescription>
              </div>
              <Dialog open={inviteOpen} onOpenChange={setInviteOpen}>
                <DialogTrigger asChild>
                  <Button className="gap-2">
                    <UserPlus className="h-4 w-4" />
                    Invite
                  </Button>
                </DialogTrigger>
                <DialogContent>
                  <DialogHeader>
                    <DialogTitle>Invite Team Member</DialogTitle>
                    <DialogDescription>
                      Add an existing OceanLog user by their account ID.
                    </DialogDescription>
                  </DialogHeader>
                  <div className="space-y-4">
                    <div className="space-y-2">
                      <Label htmlFor="invite-user-id">User ID</Label>
                      <Input
                        id="invite-user-id"
                        value={inviteUserId}
                        onChange={(e) => setInviteUserId(e.target.value)}
                        placeholder="00000000-0000-0000-0000-000000000000"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label>Role</Label>
                      <Select
                        value={inviteRole}
                        onValueChange={(v) =>
                          setInviteRole(v as TeamMember["role"])
                        }
                      >
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="admin">Admin</SelectItem>
                          <SelectItem value="staff">Staff</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                  <DialogFooter>
                    <Button
                      onClick={handleInvite}
                      disabled={inviteMember.isPending || !inviteUserId.trim()}
                    >
                      {inviteMember.isPending ? "Sending..." : "Send Invite"}
                    </Button>
                  </DialogFooter>
                </DialogContent>
              </Dialog>
            </CardHeader>
            <CardContent>
              {data.team.length === 0 ? (
                <EmptyState
                  icon={Users}
                  title="No team members"
                  description="Invite staff to help manage your dive operation."
                  actionLabel="Invite Member"
                  onAction={() => setInviteOpen(true)}
                />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Name</TableHead>
                      <TableHead>Email</TableHead>
                      <TableHead>Role</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead>Invited</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.team.map((member) => (
                      <TableRow key={member.id}>
                        <TableCell className="font-medium">
                          {member.full_name ?? "—"}
                        </TableCell>
                        <TableCell>{member.email}</TableCell>
                        <TableCell>
                          <Badge variant="outline" className="capitalize">
                            {member.role}
                          </Badge>
                        </TableCell>
                        <TableCell>
                          <Badge
                            variant={
                              member.accepted_at ? "success" : "warning"
                            }
                          >
                            {member.accepted_at ? "Active" : "Pending"}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-muted-foreground">
                          {formatDate(member.invited_at)}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="subscription" className="mt-6">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <CreditCard className="h-5 w-5" />
                Subscription
              </CardTitle>
              <CardDescription>
                Your current plan and billing status
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="flex items-center gap-4">
                <div>
                  <p className="text-sm text-muted-foreground">Current Plan</p>
                  <p className="text-2xl font-bold">
                    {tierLabels[data.subscription.tier] ?? data.subscription.tier}
                  </p>
                </div>
                <Badge
                  variant={
                    statusVariants[data.subscription.status] ?? "secondary"
                  }
                  className="capitalize"
                >
                  {data.subscription.status.replace("_", " ")}
                </Badge>
              </div>

              {data.subscription.current_period_end && (
                <p className="text-sm text-muted-foreground">
                  Current period ends{" "}
                  {formatDate(data.subscription.current_period_end)}
                </p>
              )}

              <Separator />

              <div className="grid gap-4 sm:grid-cols-2">
                <div className="rounded-lg border p-4">
                  <p className="text-sm text-muted-foreground">Sites Limit</p>
                  <p className="text-xl font-semibold">
                    {data.subscription.sites_limit}
                  </p>
                </div>
                <div className="rounded-lg border p-4">
                  <p className="text-sm text-muted-foreground">Team Limit</p>
                  <p className="text-xl font-semibold">
                    {data.subscription.team_limit}
                  </p>
                </div>
              </div>

              <div>
                <p className="mb-2 text-sm font-medium">Included Features</p>
                <ul className="space-y-1">
                  {data.subscription.features.map((feature) => (
                    <li
                      key={feature}
                      className="text-sm text-muted-foreground"
                    >
                      • {feature}
                    </li>
                  ))}
                </ul>
              </div>

              <Button variant="outline">Manage Billing</Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="export" className="mt-6">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Download className="h-5 w-5" />
                CSV Export
              </CardTitle>
              <CardDescription>
                Download your data for reporting and analysis
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <p className="text-sm text-muted-foreground">
                Export data as CSV files. Downloads are generated on demand and
                expire after 24 hours.
              </p>
              <div className="grid gap-4 sm:grid-cols-3">
                {(
                  [
                    { type: "customers", label: "Customers" },
                    { type: "sightings", label: "Sightings" },
                    { type: "dives", label: "Dive Logs" },
                  ] as const
                ).map(({ type, label }) => (
                  <div
                    key={type}
                    className="flex flex-col items-start gap-3 rounded-lg border p-4"
                  >
                    <p className="font-medium">{label}</p>
                    <Button
                      variant="outline"
                      size="sm"
                      className="gap-2"
                      onClick={() => handleExport(type)}
                      disabled={exportCsv.isPending}
                    >
                      <Download className="h-4 w-4" />
                      Export
                    </Button>
                  </div>
                ))}
              </div>
              <div className="space-y-2">
                <Label htmlFor="export-notes">Export Notes</Label>
                <Textarea
                  id="export-notes"
                  placeholder="Optional notes about this export..."
                  disabled
                />
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="compliance" className="mt-6 space-y-6">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <FileSignature className="h-5 w-5" />
                Digital waiver
              </CardTitle>
              <CardDescription>
                Guests sign at{" "}
                <code>/waiver/{data.operator.slug}</code> on mobile
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="waiver-title">Title</Label>
                <Input
                  id="waiver-title"
                  value={waiverTitle}
                  onChange={(e) => setWaiverTitle(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="waiver-body">Body</Label>
                <Textarea
                  id="waiver-body"
                  rows={8}
                  value={waiverBody}
                  onChange={(e) => setWaiverBody(e.target.value)}
                />
              </div>
              <Button
                onClick={() =>
                  upsertWaiver.mutate({ title: waiverTitle, body: waiverBody })
                }
                disabled={upsertWaiver.isPending || waiverBody.length < 20}
              >
                Publish waiver
              </Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <CreditCard className="h-5 w-5" />
                Payment links
              </CardTitle>
              <CardDescription>
                Paste a Stripe Payment Link URL and track deposits sent to divers
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>Amount (cents)</Label>
                  <Input
                    value={payAmount}
                    onChange={(e) => setPayAmount(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Description</Label>
                  <Input value={payDesc} onChange={(e) => setPayDesc(e.target.value)} />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Stripe payment URL</Label>
                <Input
                  placeholder="https://buy.stripe.com/..."
                  value={payUrl}
                  onChange={(e) => setPayUrl(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label>Stripe webhook URL (read-only, set in dashboard)</Label>
                <Input
                  value={stripeWebhookUrl}
                  onChange={(e) => {
                    setStripeWebhookUrl(e.target.value);
                    setStripeWebhookErr(validateWebhookUrl(e.target.value));
                  }}
                  placeholder="https://dashboard.stripe.com/webhooks/..."
                  aria-invalid={stripeWebhookErr != null}
                />
                {stripeWebhookErr && (
                  <p className="text-xs text-destructive">{stripeWebhookErr}</p>
                )}
                <p className="text-xs text-muted-foreground">
                  Must use HTTPS and be hosted on stripe.com.
                </p>
              </div>
              <Button
                onClick={() =>
                  createPaymentLink.mutate({
                    amount_cents: Number.parseInt(payAmount, 10),
                    description: payDesc,
                    payment_url: payUrl,
                  })
                }
                disabled={createPaymentLink.isPending || payUrl.length < 10}
              >
                Save payment link
              </Button>
              {paymentLinks.data && paymentLinks.data.length > 0 && (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Description</TableHead>
                      <TableHead>Amount</TableHead>
                      <TableHead>Link</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {paymentLinks.data.map((link) => (
                      <TableRow key={link.id}>
                        <TableCell>{link.description}</TableCell>
                        <TableCell>
                          {(link.amount_cents / 100).toFixed(2)} {link.currency}
                        </TableCell>
                        <TableCell>
                          <a
                            href={link.payment_url}
                            target="_blank"
                            rel="noreferrer"
                            className="text-ocean-600 underline"
                          >
                            Open
                          </a>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}
