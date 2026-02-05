# 🏛️ Documento de Definición Lógica: Módulo PasaTanda Core

## 1. Filosofía y Arquitectura Base

El contrato no funcionará como una bóveda pasiva, sino como un **Gestor de Fondos Automatizado y Atómico**.

* **Modelo de Objeto:** Se utilizará el modelo de **Shared Object** (Objeto Compartido). Cada "Tanda" es un objeto único que vive en la red, accesible públicamente pero modificable solo bajo reglas estrictas.
* **Atomicidad DeFi:** Se aplica la regla de "Dinero Activo". El contrato **nunca** debe retener tokens USDC en su estado interno entre transacciones. En el mismo bloque que recibe fondos, debe enviarlos al protocolo de préstamos (Navi).
* **Inmutabilidad del Juego:** Las reglas sociales (quién participa y en qué orden) se "congelan" al momento de la creación y son matemáticamente imposibles de alterar después.

---

## 2. Reglas de Negocio Inquebrantables (Constraints)

Lo que el contrato **DEBE** hacer y lo que **NO DEBE** permitir bajo ninguna circunstancia.

### ✅ Lo que DEBE hacer

1. **Respetar la Autoridad del Turno (zkLogin):** Solo permitir la ejecución del retiro si la transacción está firmada por la dirección **zkLogin** correspondiente al participante de la ronda actual (índice 0, 1, etc.), independientemente de hacia dónde se envíen los fondos finalmente.
2. **Segregar Capital de Rendimiento:** Mantener una contabilidad estricta que separe el *Principal* (que se retira hacia la Wallet del Usuario o la Bóveda Fiat) del *Yield* generado en Navi (que permanece acumulándose hasta el final de la tanda o el barrido a ARC).
3. **Permitir Depósitos Atribuidos (Patrón Relayer/PTB):** Aceptar depósitos donde la dirección que firma la transacción (`Sender`: Backend/Relayer) es distinta a la dirección del dueño de los fondos, específicamente para soportar **PTBs atómicas** que traen liquidez desde redes EVM (vía CCTP) o depósitos Fiat, acreditando el saldo internamente a la `user_address` especificada en los argumentos.
4. **Ruteo Condicional de Salida:** Implementar dos vías de retiro exclusivas en el método de `payout`, seleccionables por el usuario:
* **Vía Nativa (Sui):** Transferencia directa de USDC a la dirección del firmante (`ctx.sender`).
* **Vía Fiat (Vault):** Transferencia de USDC a una dirección de `Vault` predefinida (hardcoded o en config) y emisión obligatoria de un evento (`FiatWithdrawalRequested`) para que el Backend orqueste la transferencia bancaria y el posterior barrido de liquidez hacia ARC.




### ❌ Lo que NO DEBE hacer (Anti-Patterns)

1. **No guardar USDC Líquido:** El `struct` del objeto Tanda no debe tener un campo `Balance<USDC>` permanente. Solo debe guardar los recibos/tickets de depósito de Navi.
2. **No modificar Participantes:** No deben existir funciones para agregar, quitar o reordenar usuarios una vez creada la Tanda.
3. **No mezclar flujos:** El "Fondo de Garantía" no debe usarse para pagar los pozos mensuales. Son cubetas contables separadas.
4. **No depender de Cron Jobs On-Chain:** El contrato es pasivo; no puede "despertarse" solo. Depende de que el Backend o el Usuario llamen a las funciones para ejecutar los cambios de estado (avanzar ronda, invertir, retirar).

---

## 3. Definición Detallada de Funciones y Lógica

A continuación, se describe la lógica interna de cada función pública que expondrá el módulo `pasatanda::core`.

### A. Función: Creación de Tanda (`create_tanda`)

Esta es la función constructora que define las reglas inmutables del juego.

* **Entradas:** Lista de direcciones (participantes), monto de la cuota mensual, monto de la garantía requerida, y (opcionalmente) la dirección de la `Bóveda Fiat` autorizada.
* **Lógica:**
1. Valida que haya al menos 2 participantes.
2. Establece el orden de turnos basándose estrictamente en el orden del arreglo de direcciones recibido.
3. Inicializa los contadores: Ronda actual en 0, saldos en 0.
4. Crea el objeto y lo hace compartido (`share_object`), transfiriendo la autoridad administrativa al creador (el usuario).



### B. Función: Depósito de Garantía (`deposit_guarantee`)

Se ejecuta al inicio para constituir el fondo de seguridad (Sticky Liquidity).

* **Entradas:** El objeto Tanda, el objeto de almacenamiento de Navi, y las monedas (USDC).
* **Lógica Atómica:**
1. Verifica que la Tanda esté en fase de "Inicio".
2. Registra en la contabilidad interna que el Usuario X ya pagó su garantía.
3. Toma las monedas USDC e **inmediatamente** llama a la función de suministro (`supply`) de Navi.
4. Guarda el comprobante de Navi dentro del objeto Tanda.
5. **Segregación:** Asegura que este monto se registre como "Fondo de Garantía" y no se mezcle con el "Pozo de la Ronda".



### C. Función: Pagar Cuota (`deposit_payment`)

Esta función es polimórfica y soporta los 3 métodos de ingreso (Nativo, Fiat y EVM Bridge) mediante el patrón **"Deposit For"**.

* **Entradas:** El objeto Tanda, el objeto Navi, las monedas USDC (Coin object), y la dirección `beneficiario` (quién recibe el crédito en la tanda).
* **Lógica:**
1. **Desacople de Identidad:** Permite explícitamente que la dirección que firma la transacción (`Sender`) sea diferente a la dirección del `beneficiario`.
* *Caso SUI:* Sender y Beneficiario son el mismo.
* *Caso Fiat/EVM:* Sender es el Backend (Relayer) y Beneficiario es el Usuario.


2. **Validación de Monto:** Suma el valor del Coin recibido al "Saldo de la Ronda Actual" del beneficiario especificado.
3. **Inversión Inmediata:** Ejecuta la inyección de liquidez en Navi (`supply`) en la misma transacción. El dinero nunca se queda "quieto" en el objeto Tanda.
4. **Estado de Ronda:** Si el pago completa la cuota total, marca la participación del usuario como "Completada" para esa ronda.



### D. Función: Retiro de Pozo (`payout_round`)

Gestiona la salida de fondos y decide el destino (Crypto o Fiat) basado en la instrucción del usuario.

* **Entradas:** El objeto Tanda, el objeto Navi, el `tipo_retiro` (Wallet o Fiat), y (si aplica) la dirección de la Bóveda Fiat.
* **Lógica:**
1. **Verificación de Turno Estricta:** Verifica matemáticamente que la transacción haya sido firmada por la dirección **zkLogin** correspondiente al participante del turno actual. Si firma el Backend u otro usuario, la transacción falla.
2. **Cálculo del Principal:** Calcula el monto exacto del pozo (solo capital aportado) sin tocar los intereses generados (Yield).
3. **Retiro de Navi:** Solicita a Navi un retiro (`withdraw`) por el monto del Principal.
4. **Ruteo Condicional (Switch):**
* **Caso A (Crypto SUI):** Transfiere los USDC retirados directamente a la dirección del firmante (`ctx.sender`).
* **Caso B (Fiat):** Transfiere los USDC retirados a la dirección de la **Bóveda de Liquidez del Backend** (validada contra config o hardcode) y **EMITE** un evento inmutable `FiatWithdrawalRequested` conteniendo el ID del usuario, monto y timestamp.


5. **Avance de Ronda:** Incrementa el contador de `ronda_actual + 1` y reinicia los saldos parciales.



### E. Función: Liquidación Final (`close_tanda`)

Ocurre al finalizar el ciclo completo.

* **Entradas:** Admin o Trigger automático.
* **Lógica:**
1. Solicita a Navi el **Retiro Total** (Withdraw All). Esto recupera las Garantías + todo el Yield acumulado.
2. Devuelve las garantías originales a los participantes (sujeto a reglas de cumplimiento).
3. El excedente (Yield) se distribuye o se envía a la Tesorería según el modelo de negocio.



---

## 4. User Journeys (Perspectiva del Contrato)

### Flujo 1: Ingreso Nativo (Sui Wallet)

1. **Origen:** Usuario desde su Frontend en Sui.
2. **Acción:** Firma una transacción llamando a `deposit_payment` donde `Sender` = Usuario y `Beneficiario` = Usuario.
3. **Resultado:** Los fondos se mueven de la wallet del usuario -> Tanda -> Navi.

### Flujo 2: Ingreso Fiat (Backend Relayer)

1. **Origen:** Usuario transfiere dinero al Banco local. El Backend detecta el ingreso.
2. **Acción:** El Backend (usando su wallet de Gas) firma una transacción PTB.
* Toma USDC de su propia liquidez o boveda.
* Llama a `deposit_payment` donde `Sender` = Backend y `Beneficiario` = Usuario.


3. **Resultado:** El contrato acredita el pago al Usuario, aunque los fondos vinieron técnicamente del Backend.

### Flujo 3: Ingreso EVM Cross-Chain (Hot Potato / CCTP)

1. **Origen:** Usuario quema USDC en Base/Uniswap con destino a la wallet del Backend (Relayer).
2. **Acción:** El Backend detecta la atestación de Circle y construye una PTB atómica ("Hot Potato"):
* **Op 1:** `cctp::receive_message` (Crea el objeto Coin USDC temporalmente).
* **Op 2:** Pasa ese Coin directamente a `deposit_payment` con `Beneficiario` = Usuario.


3. **Resultado:** El Backend paga el gas, pero nunca custodia los fondos. El USDC nace del puente y entra a la Tanda en el mismo milisegundo.

### Flujo 4: Retiro (Payout)

1. **Pre-condición:** Es el turno del Usuario X.
2. **Decisión:** El Usuario X selecciona en el Frontend:
* *Opción A (Crypto):* El contrato envía USDC a su wallet.
* *Opción B (Fiat):* El contrato envía USDC a la `Wallet Bóveda` del Backend y emite evento.


3. **Post-Proceso Fiat:** El Backend escucha el evento, transfiere dinero bancario al usuario y acumula los USDC en la Bóveda.
* *Nota:* Semanalmente, un proceso externo barrerá los fondos de esta Bóveda hacia **ARC** para proveer liquidez institucional.



---

## 5. Resumen de Datos del Objeto (Storage)

El objeto `Tanda` deberá almacenar mínimamente:

* `id`: Identificador único (UID).
* `participants`: Vector de direcciones (Inmutable). Define el orden de turnos.
* `current_round`: Índice del turno actual (u64).
* `principal_balance`: Monto total de capital aportado (sin intereses) actualmente en juego.
* `yield_balance`: (Contable) Estimación o rastro de los intereses generados separados del principal.
* `round_balances`: Tabla/Mapa `{address -> u64}` que rastrea cuánto ha pagado cada usuario en la ronda actual.
* `guarantee_balances`: Tabla/Mapa `{address -> u64}` para rastrear quién pagó la garantía inicial.
* `navi_receipt`: El objeto o referencia que rastrea la posición en el protocolo Navi (donde está el dinero real).
* `vault_config`: (Opcional) Dirección autorizada para recibir los fondos en caso de retiro Fiat.