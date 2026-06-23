import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Calendar } from 'lucide-react';
import { supabase } from '../../lib/auth';
import { Card, CardContent, CardHeader, CardTitle } from '../../components/ui/card';
import { Button } from '../../components/ui/button';
import { Input } from '../../components/ui/input';
import { EmptyState } from '../../components/shared/EmptyState';
import { PageSkeleton } from '../../components/shared/LoadingSkeleton';
import { AnimatedPage, AnimatedItem } from '../../components/shared/AnimatedPage';
import { useToast } from '../../components/shared/Toast';

interface BookingSlot {
  id: string;
  trip_date: string;
  depart_at: string | null;
  dive_site: { id: string; name: string; slug: string } | null;
  site_label: string | null;
  boat: { id: string; name: string } | null;
  price_cents: number;
  currency: string;
  max_capacity: number;
  booked_count: number;
  is_active: boolean;
}

const API = import.meta.env.VITE_API_URL ?? '/api/v1';

export function SlotsPage() {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const [showForm, setShowForm] = useState(false);
  const [price, setPrice] = useState('50');
  const [capacity, setCapacity] = useState('8');
  const [date, setDate] = useState(() => new Date().toISOString().split('T')[0]);

  const { data: slots, isLoading, isError, refetch } = useQuery({
    queryKey: ['operator-slots'],
    queryFn: async () => {
      const token = (await supabase.auth.getSession()).data.session?.access_token;
      const res = await fetch(`${API}/operators/me/slots`, {
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      });
      if (!res.ok) throw new Error('Failed to load slots');
      const body = await res.json();
      return (body?.data ?? body ?? []) as BookingSlot[];
    },
  });

  const createMutation = useMutation({
    mutationFn: async () => {
      const token = (await supabase.auth.getSession()).data.session?.access_token;
      const res = await fetch(`${API}/operators/me/slots`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({
          dive_site_id: null,
          trip_date: date,
          price_cents: Math.round(parseFloat(price) * 100),
          max_capacity: parseInt(capacity),
        }),
      });
      if (!res.ok) throw new Error('Failed to create');
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['operator-slots'] });
      setShowForm(false);
      toast({ title: 'Slot created', description: 'Divers can now book this slot.' });
    },
    onError: () => toast({ title: 'Failed to create slot', variant: 'error' }),
  });

  const toggleMutation = useMutation({
    mutationFn: async ({ id, active }: { id: string; active: boolean }) => {
      const token = (await supabase.auth.getSession()).data.session?.access_token;
      const res = await fetch(`${API}/operators/me/slots/${id}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({ is_active: active }),
      });
      if (!res.ok) throw new Error('Failed to toggle');
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['operator-slots'] });
    },
  });

  if (isLoading) return <PageSkeleton />;
  if (isError) {
    return (
      <EmptyState
        icon={Calendar}
        title="Couldn’t load booking slots"
        description="There was a problem fetching your published slots."
        actionLabel="Retry"
        onAction={() => refetch()}
      />
    );
  }

  return (
    <AnimatedPage>
      <AnimatedItem>
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Booking Slots</h1>
          <p className="text-muted-foreground">Publish bookable dive slots for customers</p>
        </div>
        <Button onClick={() => setShowForm(!showForm)}>
          {showForm ? 'Cancel' : 'New slot'}
        </Button>
      </div>
      </AnimatedItem>

      {showForm && (
        <AnimatedItem>
        <Card>
          <CardHeader><CardTitle>Create booking slot</CardTitle></CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="text-sm font-medium">Date</label>
                <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
              </div>
              <div>
                <label className="text-sm font-medium">Price (EUR)</label>
                <Input type="number" min="0" step="5" value={price} onChange={(e) => setPrice(e.target.value)} />
              </div>
              <div>
                <label className="text-sm font-medium">Max divers</label>
                <Input type="number" min="1" max="100" value={capacity} onChange={(e) => setCapacity(e.target.value)} />
              </div>
            </div>
            <Button onClick={() => createMutation.mutate()}>Publish slot</Button>
          </CardContent>
        </Card>
        </AnimatedItem>
      )}

      <AnimatedItem>
      {!slots?.length ? (
        <EmptyState
          icon={Calendar}
          title="No booking slots"
          description="Create your first bookable slot for customers to book online."
        />
      ) : (
        <div className="grid gap-4">
          {slots.map((slot) => (
            <Card key={slot.id}>
              <CardContent className="flex items-center justify-between p-4">
                <div>
                  <div className="font-medium">
                    {slot.dive_site?.name ?? slot.site_label ?? 'General slot'}
                  </div>
                  <div className="text-sm text-muted-foreground">
                    {slot.trip_date}
                    {slot.depart_at ? ` · ${slot.depart_at.split('T')[1]?.substring(0, 5)}` : ''}
                    {slot.boat ? ` · ${slot.boat.name}` : ''}
                  </div>
                  <div className="text-sm">
                    {slot.booked_count}/{slot.max_capacity} booked ·
                    {slot.price_cents > 0 ? ` \u20AC${(slot.price_cents / 100).toFixed(2)}` : ' Free'}
                  </div>
                </div>
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => toggleMutation.mutate({ id: slot.id, active: !slot.is_active })}
                  >
                    {slot.is_active ? 'Pause' : 'Activate'}
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
      </AnimatedItem>
    </AnimatedPage>
  );
}
