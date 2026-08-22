# Auth — obsoleto

Este documento describía el flujo anterior (Supabase Auth en el cliente + JWT). **Ya no aplica**: el backend tiene auth propia (`/auth/signup`, `/auth/login`, token opaco de 90 días, `/auth/logout`, `/auth/password`, `/auth/delete-account`).

La referencia vigente es [`apps/backend/API.md`](apps/backend/API.md) (sección *Auth*). La app Flutter la implementa en `apps/mobile/lib/data/repositories/auth_repository.dart` y guarda el token en `apps/mobile/lib/data/api/token_store.dart` (flutter_secure_storage). Ver también [API_CONTRACT.md](API_CONTRACT.md).
