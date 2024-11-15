# Persist Cloud Shell data to avoid accidental closure

## Reset User Settings

* If this is your first time using Cloud Shell, skip to [here](#set-up-storage-account)
* If you already set up Cloud Shell without Storage Account, reset your user settings by choosing **Settings** in the top panel. Next, choose **Reset User Settings**

<img src="img/reset.png" alt="Reset user settings" width="960" height="600">

* Click **Reset** to confirm

<img src="img/reset_confirm.png" alt="Confirm reset" width="960" height="600">

## Set Up Storage Account

* Choose **Bash** as shell mode

<img src="img/choose_shell.png" alt="Choose Bash" width="960" height="600">

* Next, choose **Mount storage account** and search for **Cloud Compete Testing** under *Storage account subscription*

<img src="img/choose_storage.png" alt="Choose storage" width="960" height="600">

* Then choose **Select existing storage account** and click **Next**

<img src="img/confirm_existing.png" alt="Choose existing storage" width="960" height="600">

* Fill in the *Resource group* with **compete-labs** and *Storage account name* with **akstelescopecompetelabs**
* In *File share* section, choose **Create a file share** and type your name or useralias under *Name* and click *Ok*
* Once all information is filled in, click **Select** and wait for CloudShell session to be open

<img src="img/fill_in.png" alt="ill in information" width="960" height="600">

* Once CloudShell is ready, you can run `ls` command and look for `clouddrive` folder to confirm that storage account is successfully mounted

<img src="img/confirm_clouddrive.png" alt="Confirm clouddrive" width="960" height="600">