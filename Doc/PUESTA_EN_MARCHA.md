# Puesta en Marcha — Backend Supabase

## 1. Desarrollo Local (Supabase CLI)

```bash
cd Backend
npx supabase start
```

Al aplicar migraciones y semilla (`E3`):

```bash
npx supabase db reset
```

## 2. Vinculación con Proyecto Remoto (Staging / Producción)

> Las cuentas de infraestructura deben crearse bajo titularidad de la organización Tokyo Street en la región **South America (São Paulo)**, habilitando **Anonymous Sign-Ins** en _Authentication → Providers_.

```bash
cd Backend
npx supabase login
npx supabase link --project-ref <PROJECT_REF>
npx supabase db push
```

## 3. Despliegue de Edge Function (Entrega 2)

```bash
npx supabase secrets set SITE_URL=https://tu-dominio.com
npx supabase functions deploy admin-create-stand-users
```
