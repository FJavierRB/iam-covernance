# copilot-instructions.md


## Contexto del proyecto

- Soy el admin de una cuenta (miembro de una organización) y necesito controlar quien hace qué y sobre identificar los gastos facturables
- Los usuarios se daran de alta para sus proyectos, por lo que la base es el proyecto. Ver /config/projects.json
- No tengo acceso a la cuenta admin de la organización
- Crear con CDK las políticas, roles, usuarios etc... necesarios
- Ahora tengo una estrutura básica ya en cdk para desplegar 
- Usar scripts (carpeta sripts) para lo que sea posible
- De momento solo hay perfiles (grupos) de "developers" y "viewers", en el futuro ueden salir más

## Objetivo

- Definición políticas a aplicar para el uso de la cuenta a proyecots/usuarios
- Dar de alta a los usuarios y proyectos que aparecen en /config/projects.json aplicando las políticas y roles configurados

## Políticas a aplicar a todos los usuarios
- Solo podran crear los servicios que aparecen en allowedServices del config/projects.json
- Todos los servicios deben tener las etiquetas señaladas en /config/tags.json como mínimo
- Todos los nombres deben tner el prefijo que parezca en el archivo /config/prefix.json
- No debe haber problema a la hora de que los usuarios creen los servicios asociados, no quiero recibir correos con errores para crear servicios que se supone que pueden crear y usar.
- Ningún usuario excepto si tiene permisos admin, puede crear servicios o modificar nada desde consola, todo debe ser desde IaC, inicialmente desde CDK (luego, tal vez desde terraform). Solo podrá acceder a consola en modo "viewer".

## Reglas
1. Escribe siempre en castellano (España).
2. No uses iconos ni emoticonos en el código ni en archivos.
3. No inventes servicios, propiedades o nombres. Si falta un dato, deja un TODO claro o lee el valor desde configuración.
4. Todo nombre de recurso, etiqueta y ARN debe ser configurable (por contexto CDK o fichero de configuración). Prohibido hardcodear.
5. Seguridad por defecto: mínimo privilegio (IAM), secretos en Secrets Manager, cifrado con KMS si aplica.
6. Observabilidad por defecto: logs en CloudWatch, métricas y trazas donde proceda.



