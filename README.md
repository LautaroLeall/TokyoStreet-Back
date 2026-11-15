# Tokyo Street 3.ª Edición — Backend (Supabase + PostgreSQL)

Repositorio oficial de base de datos PostgreSQL, funciones RPC atómicas (`SECURITY DEFINER`), políticas Row Level Security (RLS) de acceso cero directo y Edge Functions para **Tokyo Street — 3.ª edición** (Pasaporte Digital de 15 Sellos).

## Estructura del Repositorio

```text
Backend/
├── Doc/
│   ├── BITACORA.md                             # Registro cronológico de avances y migraciones
│   ├── ESQUEMA_BD.md                           # Modelo relacional y contrato de funciones RPC
│   ├── POLITICAS_RLS.md                        # Matriz de aislamiento y seguridad cero-acceso-directo
│   └── PUESTA_EN_MARCHA.md                     # Guía de inicialización local y despliegue con Supabase CLI
├── supabase/
│   ├── config.toml                             # Configuración de Supabase CLI (sesiones anónimas activas)
│   ├── seed.sql                                # Semilla de configuración y catálogo de 70 stands
│   ├── functions/
│   │   ├── deno.json                           # Configuración de runtime Deno
│   │   └── admin-create-stand-users/index.ts   # Edge Function para aprovisionar/resetear las 70 cuentas
│   └── migrations/
│       ├── 20261109000001_schema_base.sql           # 10 tablas, enums, restricciones e índices
│       ├── 20261109000002_participant_functions.sql # Helpers de seguridad y RPCs de /pasaporte
│       ├── 20261109000003_stand_functions.sql       # Núcleo FOR UPDATE (_credit_stamp), /s/:token y /stand
│       ├── 20261109000004_org_functions.sql         # RPCs administrativas de /org (Mesa 70, CSV, control)
│       └── 20261109000005_security_rls.sql          # Políticas RLS forzadas y GRANTs quirúrgicos
├── .env.example                                # Plantilla de variables de entorno
└── .gitignore                                  # Blindaje estricto de credenciales y archivos temporales
```

## Índice de Documentación Técnica

- [`Doc/BITACORA.md`](./Doc/BITACORA.md): Registro cronológico de avances, modularización SQL y decisiones técnicas.
- [`Doc/ESQUEMA_BD.md`](./Doc/ESQUEMA_BD.md): Modelo relacional de las 10 tablas y contrato de funciones RPC por migración.
- [`Doc/POLITICAS_RLS.md`](./Doc/POLITICAS_RLS.md): Reglas Row Level Security, aislamiento de datos personales y matriz por rol.
- [`Doc/PUESTA_EN_MARCHA.md`](./Doc/PUESTA_EN_MARCHA.md): Pasos para vincular Supabase CLI, correr migraciones y desplegar Edge Functions.
