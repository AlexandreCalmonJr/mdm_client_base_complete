# **MDM Client Base: Gestão de Dispositivos Android Simplificada**

Bem-vindo ao **MDM Client Base**, uma solução moderna e intuitiva para o gerenciamento eficiente de dispositivos Android. Desenvolvido com Flutter, este aplicativo oferece uma interface limpa e funcionalidades robustas para otimizar o controlo e a segurança dos seus equipamentos.

## **✨ Destaques das Funcionalidades**

* **Provisionamento Rápido via QR Code**: Configure novos dispositivos Android como Device Owner em segundos, utilizando um simples scan de QR code. A inicialização é ágil e sem complicações.  
* **Gerenciamento Inteligente de APKs**: Baixe e instale aplicações de forma centralizada a partir do seu servidor MDM. O aplicativo lida automaticamente com as permissões necessárias para garantir uma instalação suave em diversas versões do Android.  
* **Monitorização Contínua em Segundo Plano**: Um serviço em segundo plano dedicado garante que o seu dispositivo esteja sempre ligado ao servidor MDM, enviando dados vitais e recebendo comandos em tempo real, mesmo quando o aplicativo não está em uso.  
* **Notificações Claras e Oportunas**: Receba alertas instantâneos sobre o estado das operações, como instalações de APKs concluídas ou erros, mantendo-o sempre informado.  
* **Segurança de Ponta**: Suas informações sensíveis, como tokens de autenticação, são armazenadas de forma segura utilizando criptografia robusta.  
* **Visão Geral Abrangente do Dispositivo**: Obtenha dados cruciais sobre o dispositivo, incluindo nível da bateria, endereços IP e MAC, que são enviados periodicamente para o servidor MDM para uma gestão completa.  
* **Configuração Descomplicada**: Atualize facilmente as configurações do servidor, dados de identificação do dispositivo e tokens de autenticação através de uma interface intuitiva, com as alterações a serem aplicadas instantaneamente.

## **🚀 Primeiros Passos**

Este projeto foi construído com Flutter para oferecer uma experiência de usuário fluida e multiplataforma.

Para começar com o desenvolvimento Flutter, consulte os recursos oficiais:

* [Lab: Crie seu primeiro aplicativo Flutter](https://docs.flutter.dev/get-started/codelab)  
* [Cookbook: Exemplos úteis de Flutter](https://docs.flutter.dev/cookbook)  
* [Documentação Online do Flutter](https://docs.flutter.dev/)

### **Pré-requisitos**

* Flutter SDK instalado.  
* Android Studio ou VS Code com os plugins Flutter e Dart.  
* Um dispositivo Android físico para testar as funcionalidades de Device Owner e provisionamento.

### **Instalação e Configuração**

1. **Clone o Repositório:**  
<<<<<<< HEAD
   git clone https://github.com/your\_username/mdm\_client\_base.git  
=======
   git clone <https://github.com/your\_username/mdm\_client\_base.git>  
>>>>>>> retorno
   cd mdm\_client\_base

2. **Obtenha as Dependências:**  
   flutter pub get

3. **Configuração do Ambiente Android:**  
   * **AndroidManifest.xml**: Este ficheiro (localizado em android/app/src/main/AndroidManifest.xml) contém todas as permissões essenciais e declarações para o funcionamento do MDM, incluindo:  
     * Permissões de administração do dispositivo (BIND\_DEVICE\_ADMIN).  
     * Acesso à internet, estado de rede e Wi-Fi.  
     * Gestão de armazenamento externo (para Android 10 e anteriores, e Android 11+).  
     * Permissões para instalação e desinstalação de aplicações.  
     * Serviços em primeiro plano.  
     * Receção de eventos de inicialização do sistema.  
     * Declarações específicas para o DeviceAdminReceiver e FileProvider.  
     * Consultas para visibilidade de pacotes no Android 11+.  
   * **device\_admin.xml**: Em android/app/src/main/res/xml/device\_admin.xml, este XML define as políticas de administração que o aplicativo pode aplicar, como controlo de palavras-passe, câmera, e gestão de pacotes.  
   * **file\_paths.xml**: Essencial para o FileProvider, este ficheiro (android/app/src/main/res/xml/file\_paths.xml) assegura que as permissões de URI para acesso a ficheiros, incluindo downloads, são concedidas corretamente.  
   * **build.gradle.kts (nível do aplicativo)**: (android/app/build.gradle.kts) configura a compilação Android, garantindo compatibilidade com Java 11+, desugaring de bibliotecas e suporte a multidex.  
   * **build.gradle.kts (nível do projeto)**: (android/build.gradle.kts) define as dependências e repositórios globais do processo de compilação.  
   * **Ficheiros Kotlin (Android Nativo)**:  
     * MainActivity.kt: A ponte entre o Flutter e o Android nativo, responsável por gerir a comunicação do MethodChannel, verificar o estado de Device Owner e extrair dados de provisionamento.  
     * DeviceAdminReceiver.kt: O coração da administração do dispositivo, onde são tratados eventos cruciais como a conclusão do provisionamento e a aplicação de políticas iniciais.  
     * BootReceiver.kt: Garante que a aplicação se inicie automaticamente com o dispositivo.  
     * NotificationChannel.kt: Abstrai a criação de canais de notificação e a exibição de notificações.  
     * IntentResultReceiver.kt e UninstallResultReceiver.kt: Lidam com os resultados de instalações e desinstalações de pacotes, respetivamente.  
     * IntentSenderReceiver.kt: Apoia a receção de resultados de instalações de pacotes.  
4. **Execute o Aplicativo:**  
   flutter run

## **🎯 Como Usar**

### **Provisionamento de Dispositivo**

Para provisionar um dispositivo Android como Device Owner:

1. **Gere o QR Code**: Utilize o ficheiro apk pronto/html/index.html no seu navegador.  
   * Preencha os campos essenciais: **URL de Download do APK**, **Checksum SHA-256 do APK**, **Nome do Pacote** (ex: com.example.mdm\_client\_base) e **Nome do Componente Admin** (ex: com.example.mdm\_client\_base/.DeviceAdminReceiver).  
   * Opcionalmente, configure as informações de Wi-Fi se o dispositivo precisar de rede durante o provisionamento.  
   * Clique em "Gerar QR Code".  
2. **Redefina o Dispositivo**: Certifique-se de que o dispositivo Android está nas configurações de fábrica.  
3. **Ative o Scanner de QR Code**: Na tela de boas-vindas do dispositivo, toque 6 vezes rapidamente no mesmo local para ativar o scanner.  
4. **Escaneie o QR Code**: Use a câmera do dispositivo para ler o QR code gerado.  
5. **Conclusão do Provisionamento**: O dispositivo fará o download, instalará e configurará o aplicativo como Device Owner, aplicando as políticas iniciais.

### **Gerenciamento de APKs**

Na tela "Gerenciador de APKs", poderá ver uma lista de aplicações disponíveis no servidor. Basta selecionar e o aplicativo cuidará do download e da instalação, solicitando as permissões necessárias de forma inteligente.

### **Configurações**

A tela "Configurações" permite-lhe personalizar o host e a porta do servidor MDM, o número de série do dispositivo, IMEI e o token de autenticação. As alterações são salvas e o serviço em segundo plano é reiniciado para que as novas configurações entrem em vigor imediatamente.

## **🛠️ Notas de Desenvolvimento**

* **Logs Detalhados**: O aplicativo utiliza o pacote logging para fornecer logs detalhados, visíveis no console de depuração, facilitando a resolução de problemas.  
* **Serviço Robusto em Segundo Plano**: Alimentado por flutter\_background\_service, o aplicativo realiza tarefas críticas em segundo plano, como o envio de dados e a verificação de comandos, garantindo a continuidade da gestão.  
* **Comunicação Nativa Eficiente**: A comunicação entre o Flutter e o código nativo Android é realizada através de MethodChannel (com.example.mdm\_client\_base/device\_policy), assegurando uma integração fluida.  
* **Armazenamento de Dados Confidencial**: flutter\_secure\_storage é empregado para proteger dados sensíveis, como tokens de autenticação, utilizando criptografia forte.  
* **Adaptação a Versões Android**: O tratamento de permissões e o salvamento de ficheiros são adaptados para funcionar corretamente em diferentes versões do Android, desde as mais antigas até o Android 11+.

## **📦 Dependências Essenciais**

O projeto conta com os seguintes pacotes-chave do Flutter e Dart:

* cupertino\_icons  
* battery\_plus  
* connectivity\_plus  
* device\_info\_plus  
* flutter\_background\_service  
* http  
* intl  
* path\_provider  
* permission\_handler  
* shared\_preferences  
* logger  
* network\_info\_plus  
* flutter\_secure\_storage  
* logging  
* flutter\_local\_notifications

## **🤝 Contribuições**

Contribuições são muito bem-vindas\! Se tiver sugestões, encontrar um bug ou quiser adicionar uma nova funcionalidade, sinta-se à vontade para abrir uma issue ou enviar um pull request.

## Criador : Alexandre de Souza Calmon Junior
