-- Risposta a un messaggio specifico (reply "in linea", stile Instagram/WhatsApp).
-- Nessuna nuova policy RLS necessaria: è solo una colonna in più sulla stessa
-- riga di "messages", già coperta dalle policy select/insert esistenti.

alter table public.messages
  add column if not exists reply_to_id uuid references public.messages(id) on delete set null;

create index if not exists messages_reply_to_idx
  on public.messages (reply_to_id);
